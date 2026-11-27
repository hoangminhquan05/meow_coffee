// POST /shipper/orders/{orderId} – shipper giao đơn mình đang giữ (bước 9):
//   { action: "picked_up" }                    Đã lấy hàng: Sẵn sàng → Đang giao
//   { action: "arrived" }                      Đã đến nơi (bắt đầu tính giờ chờ – O29)
//   { action: "call" }                         Bấm Gọi (app mở tel:, Worker đếm số lần)
//   { action: "delivered", collected: true }   Đã giao (+ xác nhận đã thu tiền nếu có) → Hoàn thành
//   { action: "failed", reason }               Giao không thành công (đủ giờ chờ + số lần gọi) → Giao thất bại
import type { FirebaseUserClaims } from '../firebase/idToken';
import {
  arrayAppend,
  arrayRemove,
  Firestore,
  increment,
  patchWrite,
  serverTime,
  Ts,
  type FsTransform,
} from '../firebase/firestore';
import { MAX_NOTE, OrderRuleError } from '../orders/rules';
import { amountToCollect, failureBlocker, parseFailureConfig, vnDayKey } from '../dispatch/score';

const obj = (v: unknown) => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {});

export type ShipperAction = 'picked_up' | 'arrived' | 'call' | 'delivered' | 'failed';

export interface ShipperRequest {
  action: ShipperAction;
  collected?: boolean;
  reason?: string;
}

export function parseShipperRequest(body: unknown): ShipperRequest {
  const b = obj(body);
  switch (b.action) {
    case 'picked_up':
    case 'arrived':
    case 'call':
      return { action: b.action };
    case 'delivered':
      return { action: 'delivered', collected: b.collected === true };
    case 'failed': {
      const reason = typeof b.reason === 'string' ? b.reason.trim() : '';
      if (!reason) throw new OrderRuleError(400, 'invalid_request', 'Vui lòng chọn lý do');
      if (reason.length > MAX_NOTE) throw new OrderRuleError(400, 'invalid_request', 'Lý do quá dài');
      return { action: 'failed', reason };
    }
    default:
      throw new OrderRuleError(400, 'invalid_request', 'Thao tác không hợp lệ');
  }
}

const FROM: Record<ShipperAction, string> = {
  picked_up: 'ready',
  arrived: 'delivering',
  call: 'delivering',
  delivered: 'delivering',
  failed: 'delivering',
};

/** Đơn của chính shipper này và đúng trạng thái (thuần, để test). */
export function checkShipperAction(order: Record<string, unknown> | null, uid: string, action: ShipperAction): void {
  if (!order || order.channel !== 'online') throw new OrderRuleError(404, 'order_missing', 'Không tìm thấy đơn');
  if (obj(obj(order.delivery).shipper).id !== uid) {
    throw new OrderRuleError(403, 'not_your_order', 'Đơn này không còn do bạn giao');
  }
  if (order.status !== FROM[action]) {
    throw new OrderRuleError(409, 'wrong_status', 'Đơn vừa được cập nhật, vui lòng xem lại');
  }
}

export interface ShipperOrderResult {
  order_id: string;
  status: string;
  call_attempts?: number;
  collected?: number;
}

export async function handleShipperOrder(
  db: Firestore,
  claims: FirebaseUserClaims,
  orderId: string,
  body: unknown,
  now = new Date(),
): Promise<ShipperOrderResult> {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(orderId)) {
    throw new OrderRuleError(400, 'invalid_request', 'Mã đơn không hợp lệ');
  }
  const req = parseShipperRequest(body);
  const [user, settings] = await db.getMany([`users/${claims.uid}`, 'settings/shop']);
  if (user?.data.role !== 'shipper' || user.data.is_active !== true) {
    throw new OrderRuleError(403, 'not_shipper', 'Chỉ shipper mới thao tác được');
  }
  const by = { id: claims.uid, name: String(user.data.name ?? ''), role: 'shipper' };
  const history = (status: string) => arrayAppend('status_history', { status, at: new Ts(now), by });
  const path = `orders/${orderId}`;

  return db.runOptimistic<ShipperOrderResult>(async (tx) => {
    const order = await db.get(path, tx);
    checkShipperAction(order?.data ?? null, claims.uid, req.action);
    const o = order!.data;
    const delivery = obj(o.delivery);
    const base = { updateTime: order!.updateTime };

    switch (req.action) {
      case 'picked_up':
        return {
          writes: [
            patchWrite(
              order!.name,
              { status: 'delivering', 'delivery.picked_up_at': new Ts(now) },
              { ...base, transforms: [history('delivering'), serverTime('updated_at')] },
            ),
          ],
          result: { order_id: orderId, status: 'delivering' },
        };

      case 'arrived':
        if (delivery.arrived_at instanceof Date) {
          return { writes: [], result: { order_id: orderId, status: 'delivering' } };
        }
        return {
          writes: [
            patchWrite(order!.name, { 'delivery.arrived_at': new Ts(now) }, {
              ...base,
              transforms: [serverTime('updated_at')],
            }),
          ],
          result: { order_id: orderId, status: 'delivering' },
        };

      case 'call': {
        const calls = Array.isArray(delivery.call_attempts) ? delivery.call_attempts.length : 0;
        return {
          writes: [
            patchWrite(order!.name, {}, {
              transforms: [arrayAppend('delivery.call_attempts', new Ts(now))],
            }),
          ],
          result: { order_id: orderId, status: 'delivering', call_attempts: calls + 1 },
        };
      }

      case 'delivered': {
        const collect = amountToCollect(o);
        if (collect > 0 && !req.collected) {
          throw new OrderRuleError(400, 'collect_required', 'Vui lòng xác nhận đã thu tiền của khách');
        }
        const today = vnDayKey(now);
        const flat: Record<string, unknown> = {
          status: 'completed',
          'delivery.delivered_at': new Ts(now),
          'delivery.done_day': today,
        };
        if (o.payment_method === 'cash') flat.payment_status = 'paid';
        if (collect > 0) {
          flat.cod = { amount: collect, collected: true, collected_at: new Ts(now), settled: false, settlement_id: null };
        }
        const status = await db.get(`shipper_status/${claims.uid}`, tx);
        const statusWrites = status
          ? [
              patchWrite(status.name, statsFields(status.data, today, 'delivered'), {
                updateTime: status.updateTime,
                transforms: [
                  arrayRemove('active_order_ids', orderId),
                  ...(collect > 0 ? [increment('cod_holding', collect)] : []),
                  ...statsTransforms(status.data, today, 'delivered'),
                ],
              }),
            ]
          : [];
        return {
          writes: [
            patchWrite(order!.name, flat, {
              ...base,
              transforms: [history('completed'), serverTime('completed_at'), serverTime('updated_at')],
            }),
            ...statusWrites,
          ],
          result: { order_id: orderId, status: 'completed', collected: collect },
        };
      }

      case 'failed': {
        const blocker = failureBlocker(delivery, parseFailureConfig(settings?.data ?? null), now);
        if (blocker) throw new OrderRuleError(409, 'too_early', blocker);
        const today = vnDayKey(now);
        const status = await db.get(`shipper_status/${claims.uid}`, tx);
        return {
          writes: [
            patchWrite(order!.name, { status: 'delivery_failed' }, {
              ...base,
              transforms: [
                history('delivery_failed'),
                arrayAppend('failed_attempts', {
                  at: new Ts(now),
                  by: { id: by.id, name: by.name },
                  reason: req.reason,
                  call_attempts: Array.isArray(delivery.call_attempts) ? delivery.call_attempts.length : 0,
                }),
                serverTime('updated_at'),
              ],
            }),
            ...(status
              ? [
                  patchWrite(status.name, statsFields(status.data, today, 'failed'), {
                    updateTime: status.updateTime,
                    transforms: [arrayRemove('active_order_ids', orderId), ...statsTransforms(status.data, today, 'failed')],
                  }),
                ]
              : []),
          ],
          result: { order_id: orderId, status: 'delivery_failed' },
        };
      }
    }
  });
}

/** Thống kê theo ngày trên shipper_status: sang ngày mới thì đặt lại. */
function statsFields(s: Record<string, unknown>, today: string, kind: 'delivered' | 'failed'): Record<string, unknown> {
  if (s.stats_day === today) return {};
  return {
    stats_day: today,
    delivered_today: kind === 'delivered' ? 1 : 0,
    failed_today: kind === 'failed' ? 1 : 0,
  };
}

function statsTransforms(s: Record<string, unknown>, today: string, kind: 'delivered' | 'failed'): FsTransform[] {
  if (s.stats_day !== today) return [];
  return [increment(kind === 'delivered' ? 'delivered_today' : 'failed_today', 1)];
}
