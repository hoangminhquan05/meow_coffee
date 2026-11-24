// POST /orders/{id}/cancel – khách tự hủy khi quán chưa xác nhận (O15).
// Đơn đã trả tiền (VietQR) mà khách hủy lúc `pending` → cần hoàn tiền (O17).
import type { FirebaseUserClaims } from '../firebase/idToken';
import { encodeFields, encodeValue, Firestore, Ts } from '../firebase/firestore';
import { MAX_NOTE, OrderRuleError } from './rules';

export const CUSTOMER_CANCELLABLE = ['awaiting_payment', 'pending'];

/** Kiểm quyền hủy (tách riêng để test). */
export function checkCustomerCancel(
  order: Record<string, unknown> | null,
  uid: string,
  reason: unknown,
): string {
  if (!order) throw new OrderRuleError(404, 'order_missing', 'Không tìm thấy đơn');
  const customer = order.customer as { id?: string } | undefined;
  if (order.channel !== 'online' || customer?.id !== uid) {
    throw new OrderRuleError(403, 'not_owner', 'Bạn không thể hủy đơn này');
  }
  if (!CUSTOMER_CANCELLABLE.includes(String(order.status))) {
    throw new OrderRuleError(
      409,
      'not_cancellable',
      'Quán đã xác nhận đơn, vui lòng nhắn Meow Shop để được hỗ trợ',
    );
  }
  const text = typeof reason === 'string' ? reason.trim() : '';
  if (!text) throw new OrderRuleError(400, 'invalid_request', 'Vui lòng chọn lý do hủy');
  if (text.length > MAX_NOTE) throw new OrderRuleError(400, 'invalid_request', 'Lý do quá dài');
  return text;
}

export async function cancelOrder(
  db: Firestore,
  claims: FirebaseUserClaims,
  orderId: string,
  body: unknown,
  now = new Date(),
): Promise<{ order_id: string; status: 'cancelled'; refund_required: boolean }> {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(orderId)) {
    throw new OrderRuleError(400, 'invalid_request', 'Mã đơn không hợp lệ');
  }
  const reasonRaw = (body as { reason?: unknown } | null)?.reason;
  const path = `orders/${orderId}`;

  return db.runTransaction(async (tx) => {
    const doc = await db.get(path, tx);
    const reason = checkCustomerCancel(doc?.data ?? null, claims.uid, reasonRaw);
    const order = doc!.data;
    const customer = order.customer as { id: string; name?: string };
    const paid = order.payment_status === 'paid';
    const by = { id: claims.uid, name: customer.name ?? '', role: 'customer' };

    const fields: Record<string, unknown> = {
      status: 'cancelled',
      payment_status: paid ? 'refunded' : order.payment_status,
      cancelled_by: by,
      cancel_reason: reason,
      ...(paid
        ? { refund: { required: true, amount: order.total, done: false } }
        : {}),
    };
    return {
      writes: [
        {
          update: { name: db.docName(path), fields: encodeFields(fields) },
          updateMask: { fieldPaths: Object.keys(fields) },
          // Không ghi nếu đơn vừa bị đổi (ví dụ quán vừa bấm xác nhận).
          currentDocument: { updateTime: doc!.updateTime },
          updateTransforms: [
            { fieldPath: 'cancelled_at', setToServerValue: 'REQUEST_TIME' },
            {
              fieldPath: 'status_history',
              appendMissingElements: {
                values: [encodeValue({ status: 'cancelled', at: new Ts(now), by })],
              },
            },
          ],
        },
      ],
      result: { order_id: orderId, status: 'cancelled' as const, refund_required: paid },
    };
  });
}
