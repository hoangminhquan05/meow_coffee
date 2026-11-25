// Cron mỗi phút: hủy đơn VietQR quá hạn chuyển khoản (O5). Tiền về sau đó sẽ
// rơi vào "Giao dịch cần kiểm tra" (đơn không còn chờ thanh toán).
import { encodeFields, encodeValue, Firestore, FirestoreError, Ts } from '../firebase/firestore';

export const SYSTEM_TIMER = { id: 'system', name: 'Hệ thống', role: 'system' };

/** Đơn đã quá hạn thanh toán chưa (thuần, để test). */
export function isPaymentExpired(order: Record<string, unknown>, now: Date): boolean {
  if (order.status !== 'awaiting_payment' || order.payment_status === 'paid') return false;
  const expires = (order.payment as { expires_at?: unknown } | undefined)?.expires_at;
  return expires instanceof Date && expires.getTime() < now.getTime();
}

export async function expireUnpaidOrders(db: Firestore, now = new Date()): Promise<number> {
  // Số đơn chờ thanh toán luôn ít → lọc theo trạng thái rồi xét hạn trong code
  // (không cần thêm composite index).
  const waiting = await db.findWhere('orders', 'status', 'awaiting_payment', 200);
  let cancelled = 0;
  for (const doc of waiting) {
    if (!isPaymentExpired(doc.data, now)) continue;
    const fields = {
      status: 'cancelled',
      cancel_reason: 'Quá hạn thanh toán',
      cancelled_by: SYSTEM_TIMER,
    };
    try {
      await db.commit([
        {
          update: { name: doc.name, fields: encodeFields(fields) },
          updateMask: { fieldPaths: Object.keys(fields) },
          // Bỏ qua nếu đơn vừa được trả tiền / thay đổi trong lúc chạy.
          currentDocument: { updateTime: doc.updateTime },
          updateTransforms: [
            { fieldPath: 'cancelled_at', setToServerValue: 'REQUEST_TIME' },
            {
              fieldPath: 'status_history',
              appendMissingElements: {
                values: [encodeValue({ status: 'cancelled', at: new Ts(now), by: SYSTEM_TIMER })],
              },
            },
          ],
        },
      ]);
      cancelled++;
    } catch (e) {
      if (e instanceof FirestoreError && (e.status === 409 || e.code === 'FAILED_PRECONDITION')) {
        continue; // đơn vừa đổi, lần chạy sau xét lại
      }
      throw e;
    }
  }
  return cancelled;
}
