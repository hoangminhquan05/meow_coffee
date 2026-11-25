// POST /webhooks/sepay – SePay báo có tiền vào tài khoản của quán (bước 6).
// Khớp đúng mã đơn + đủ tiền + đơn còn "Chờ thanh toán" → đơn sang "Chờ xác nhận".
// Mọi trường hợp khác → payment_transactions.status = needs_review cho admin (O6).
// https://docs.sepay.vn/tich-hop-webhooks.html
import { encodeFields, encodeValue, Firestore, Ts, type FsWrite } from '../firebase/firestore';

export interface SepayPayload {
  id: number;
  gateway?: string;
  transactionDate?: string;
  accountNumber?: string;
  code?: string | null;
  content?: string;
  transferType?: string;
  transferAmount?: number;
  referenceCode?: string;
  description?: string;
}

export const SYSTEM_SEPAY = { id: 'sepay', name: 'SePay', role: 'system' };

/** So sánh chuỗi không lộ thời gian (chống đoán khóa theo thời gian phản hồi). */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** SePay gửi header "Authorization: Apikey <khóa>". */
export function checkSepayAuth(header: string | null, apiKey: string | undefined): boolean {
  if (!apiKey) return false;
  const m = /^Apikey\s+(.+)$/i.exec(header ?? '');
  return !!m && safeEqual(m[1].trim(), apiKey);
}

/**
 * Tìm mã đơn online trong nội dung chuyển khoản. App hiển thị "ON231126005"
 * (mã ON-231126-005 bỏ gạch); ngân hàng có thể thêm chữ/khoảng trắng xung quanh.
 */
export function extractOrderCode(...texts: (string | null | undefined)[]): string | null {
  for (const t of texts) {
    if (!t) continue;
    const m = /ON[\s-]?(\d{6})[\s-]?(\d{3})(?!\d)/i.exec(t);
    if (m) return `ON-${m[1]}-${m[2]}`;
  }
  return null;
}

export type ReviewReason =
  | 'no_code'
  | 'order_not_found'
  | 'not_vietqr'
  | 'not_awaiting'
  | 'amount_mismatch';

export const REVIEW_REASON_TEXT: Record<ReviewReason, string> = {
  no_code: 'Nội dung chuyển khoản không có mã đơn',
  order_not_found: 'Không tìm thấy đơn theo mã trong nội dung',
  not_vietqr: 'Đơn không chọn thanh toán VietQR',
  not_awaiting: 'Đơn không còn chờ thanh toán (đã hủy / đã trả)',
  amount_mismatch: 'Số tiền chuyển không khớp tổng đơn',
};

/** Quyết định khớp đơn (thuần, để test). */
export function decideMatch(
  order: Record<string, unknown> | null,
  amount: number,
): { ok: true } | { ok: false; reason: ReviewReason } {
  if (!order) return { ok: false, reason: 'order_not_found' };
  if (order.channel !== 'online' || order.payment_method !== 'vietqr') {
    return { ok: false, reason: 'not_vietqr' };
  }
  if (order.status !== 'awaiting_payment' || order.payment_status === 'paid') {
    return { ok: false, reason: 'not_awaiting' };
  }
  if (Number(order.total) !== amount) return { ok: false, reason: 'amount_mismatch' };
  return { ok: true };
}

export interface SepayResult {
  result: 'ignored' | 'duplicate' | 'matched' | 'needs_review';
  order_code?: string;
}

export async function handleSepayWebhook(
  db: Firestore,
  payload: SepayPayload,
  now = new Date(),
): Promise<SepayResult> {
  if (typeof payload?.id !== 'number') throw new Error('invalid SePay payload');
  // Chỉ quan tâm tiền vào.
  if (payload.transferType && payload.transferType !== 'in') return { result: 'ignored' };

  const amount = Math.round(Number(payload.transferAmount ?? 0));
  const code = extractOrderCode(payload.code, payload.content, payload.description);
  const txPath = `payment_transactions/sepay_${payload.id}`;
  const order = code ? (await db.findWhere('orders', 'order_code', code, 1))[0] ?? null : null;

  return db.runTransaction<SepayResult>(async (tx) => {
    // Chống xử lý trùng: SePay có thể gửi lại cùng một giao dịch.
    if (await db.get(txPath, tx)) {
      return { writes: [], result: { result: 'duplicate', order_code: code ?? undefined } };
    }
    const fresh = order ? await db.get(`orders/${order.id}`, tx) : null;
    const decision = code ? decideMatch(fresh?.data ?? null, amount) : { ok: false as const, reason: 'no_code' as const };

    const txRecord: Record<string, unknown> = {
      provider: 'sepay',
      sepay_id: payload.id,
      gateway: payload.gateway ?? '',
      account_number: payload.accountNumber ?? '',
      amount,
      content: payload.content ?? '',
      reference_code: payload.referenceCode ?? '',
      transaction_date: payload.transactionDate ?? '',
      order_code: code,
      order_id: fresh?.id ?? null,
      status: decision.ok ? 'matched' : 'needs_review',
      reason: decision.ok ? null : decision.reason,
      reason_text: decision.ok ? null : REVIEW_REASON_TEXT[decision.reason],
    };
    const writes: FsWrite[] = [
      {
        update: { name: db.docName(txPath), fields: encodeFields(txRecord) },
        currentDocument: { exists: false },
        updateTransforms: [{ fieldPath: 'received_at', setToServerValue: 'REQUEST_TIME' }],
      },
    ];

    if (decision.ok && fresh) {
      const fields = { status: 'pending', payment_status: 'paid' };
      writes.push({
        update: {
          name: fresh.name,
          fields: encodeFields({
            ...fields,
            payment: {
              ...(fresh.data.payment as Record<string, unknown>),
              paid_amount: amount,
              paid_at: new Ts(now),
              tx_ids: [`sepay_${payload.id}`],
            },
          }),
        },
        updateMask: { fieldPaths: ['status', 'payment_status', 'payment'] },
        currentDocument: { updateTime: fresh.updateTime },
        updateTransforms: [
          {
            fieldPath: 'status_history',
            appendMissingElements: {
              values: [encodeValue({ status: 'pending', at: new Ts(now), by: SYSTEM_SEPAY })],
            },
          },
        ],
      });
    }
    return {
      writes,
      result: {
        result: decision.ok ? ('matched' as const) : ('needs_review' as const),
        order_code: code ?? undefined,
      },
    };
  });
}
