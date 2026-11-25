// POST /admin/payments/{txId}/resolve – admin xử lý "Giao dịch cần kiểm tra".
//   { action: "attach", order_code, note? } gắn tiền vào đơn → đơn thành đã trả, chờ xác nhận
//   { action: "dismiss", note }             đã xử lý ngoài app (hoàn tiền tay / bỏ qua)
import type { FirebaseUserClaims } from '../firebase/idToken';
import { encodeFields, encodeValue, Firestore, Ts, type FsWrite } from '../firebase/firestore';
import { OrderRuleError } from '../orders/rules';

/** Đơn có được gắn khoản tiền này không (thuần, để test). */
export function canAttach(order: Record<string, unknown> | null): string | null {
  if (!order) return 'Không tìm thấy đơn';
  if (order.channel !== 'online' || order.payment_method !== 'vietqr') {
    return 'Chỉ gắn được vào đơn online thanh toán VietQR';
  }
  if (order.payment_status === 'paid') return 'Đơn này đã được thanh toán';
  const expiredCancel = order.status === 'cancelled' && order.cancel_reason === 'Quá hạn thanh toán';
  if (order.status !== 'awaiting_payment' && !expiredCancel) {
    return 'Chỉ gắn được vào đơn đang chờ thanh toán hoặc bị hủy do quá hạn thanh toán';
  }
  return null;
}

export async function resolvePayment(
  db: Firestore,
  claims: FirebaseUserClaims,
  txId: string,
  body: unknown,
  now = new Date(),
): Promise<{ status: 'resolved'; resolution: 'attached' | 'dismissed'; order_code?: string }> {
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(txId)) {
    throw new OrderRuleError(400, 'invalid_request', 'Mã giao dịch không hợp lệ');
  }
  const admin = await db.get(`users/${claims.uid}`);
  if (admin?.data.role !== 'admin' || admin.data.is_active !== true) {
    throw new OrderRuleError(403, 'forbidden', 'Chỉ admin được xử lý giao dịch');
  }
  const by = { id: claims.uid, name: String(admin.data.name ?? ''), role: 'admin' };
  const b = (body ?? {}) as { action?: unknown; order_code?: unknown; note?: unknown };
  const note = typeof b.note === 'string' ? b.note.trim().slice(0, 300) : '';
  const txPath = `payment_transactions/${txId}`;

  if (b.action === 'dismiss') {
    if (!note) throw new OrderRuleError(400, 'invalid_request', 'Vui lòng ghi chú cách đã xử lý');
    return db.runTransaction(async (tx) => {
      const t = await db.get(txPath, tx);
      if (!t) throw new OrderRuleError(404, 'not_found', 'Không tìm thấy giao dịch');
      if (t.data.status !== 'needs_review') {
        throw new OrderRuleError(409, 'already_resolved', 'Giao dịch đã được xử lý');
      }
      const fields = { status: 'resolved', resolution: 'dismissed', resolved_by: by, note };
      return {
        writes: [
          {
            update: { name: t.name, fields: encodeFields(fields) },
            updateMask: { fieldPaths: Object.keys(fields) },
            currentDocument: { updateTime: t.updateTime },
            updateTransforms: [{ fieldPath: 'resolved_at', setToServerValue: 'REQUEST_TIME' }],
          },
        ],
        result: { status: 'resolved' as const, resolution: 'dismissed' as const },
      };
    });
  }

  if (b.action !== 'attach') throw new OrderRuleError(400, 'invalid_request', 'Thao tác không hợp lệ');
  const code = typeof b.order_code === 'string' ? b.order_code.trim().toUpperCase() : '';
  if (!/^ON-\d{6}-\d{3}$/.test(code)) {
    throw new OrderRuleError(400, 'invalid_request', 'Mã đơn dạng ON-ddMMyy-NNN');
  }
  const found = (await db.findWhere('orders', 'order_code', code, 1))[0];
  if (!found) throw new OrderRuleError(404, 'order_missing', `Không tìm thấy đơn ${code}`);

  return db.runTransaction(async (tx) => {
    const t = await db.get(txPath, tx);
    if (!t) throw new OrderRuleError(404, 'not_found', 'Không tìm thấy giao dịch');
    if (t.data.status !== 'needs_review') {
      throw new OrderRuleError(409, 'already_resolved', 'Giao dịch đã được xử lý');
    }
    const order = await db.get(`orders/${found.id}`, tx);
    const problem = canAttach(order?.data ?? null);
    if (problem) throw new OrderRuleError(409, 'cannot_attach', problem);
    const amount = Number(t.data.amount ?? 0);

    const orderFields = { status: 'pending', payment_status: 'paid' };
    const writes: FsWrite[] = [
      {
        update: {
          name: order!.name,
          fields: encodeFields({
            ...orderFields,
            payment: {
              ...(order!.data.payment as Record<string, unknown>),
              paid_amount: amount,
              paid_at: new Ts(now),
              tx_ids: [txId],
            },
          }),
        },
        updateMask: { fieldPaths: ['status', 'payment_status', 'payment'] },
        currentDocument: { updateTime: order!.updateTime },
        updateTransforms: [
          {
            fieldPath: 'status_history',
            appendMissingElements: {
              values: [encodeValue({ status: 'pending', at: new Ts(now), by })],
            },
          },
        ],
      },
      {
        update: {
          name: t.name,
          fields: encodeFields({
            status: 'resolved',
            resolution: 'attached',
            order_id: order!.id,
            order_code: code,
            resolved_by: by,
            note,
          }),
        },
        updateMask: {
          fieldPaths: ['status', 'resolution', 'order_id', 'order_code', 'resolved_by', 'note'],
        },
        currentDocument: { updateTime: t.updateTime },
        updateTransforms: [{ fieldPath: 'resolved_at', setToServerValue: 'REQUEST_TIME' }],
      },
    ];
    return {
      writes,
      result: { status: 'resolved' as const, resolution: 'attached' as const, order_code: code },
    };
  });
}
