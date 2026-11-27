// POST /dispatch/{orderId} – NV/admin (bước 9):
//   { action: "ready" }                         Pha xong → Sẵn sàng + gán shipper ngay
//   { action: "retry" }                         Mời lại từ đầu (xoá danh sách đã từ chối)
//   { action: "assign", shipper_id }            Gán thẳng cho shipper trong ca (đơn chưa lấy hàng)
//   { action: "redeliver" }                     Giao thất bại → giao lại (+1 lần phí ship nếu bật phí – O33)
//   { action: "cancel", reason }                Hủy đơn Sẵn sàng (hoàn tiền nếu đã trả) / Giao thất bại (không hoàn – O21)
import type { FirebaseUserClaims } from '../firebase/idToken';
import { arrayAppend, Firestore, patchWrite, serverTime, Ts, type FsWrite } from '../firebase/firestore';
import { MAX_NOTE, OrderRuleError, parseShopSettings } from '../orders/rules';
import {
  emptyDispatch,
  offerNextSafe,
  type Defer,
  releaseHolderWrites,
  releaseOfferWrites,
  type DispatchResult,
} from './dispatch';

const obj = (v: unknown) => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {});

export type StaffAction = 'ready' | 'retry' | 'assign' | 'redeliver' | 'cancel';

export interface StaffRequest {
  action: StaffAction;
  shipperId?: string;
  reason?: string;
}

/** Kiểm body (thuần, để test). */
export function parseStaffRequest(body: unknown): StaffRequest {
  const b = obj(body);
  const action = b.action;
  if (action === 'ready' || action === 'retry' || action === 'redeliver') return { action };
  if (action === 'assign') {
    if (typeof b.shipper_id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(b.shipper_id)) {
      throw new OrderRuleError(400, 'invalid_request', 'Chưa chọn shipper');
    }
    return { action, shipperId: b.shipper_id };
  }
  if (action === 'cancel') {
    const reason = typeof b.reason === 'string' ? b.reason.trim() : '';
    if (!reason) throw new OrderRuleError(400, 'invalid_request', 'Vui lòng chọn lý do');
    if (reason.length > MAX_NOTE) throw new OrderRuleError(400, 'invalid_request', 'Lý do quá dài');
    return { action, reason };
  }
  throw new OrderRuleError(400, 'invalid_request', 'Thao tác không hợp lệ');
}

/** Trạng thái đơn được phép cho từng thao tác. */
export const STAFF_FROM: Record<StaffAction, string[]> = {
  ready: ['preparing'],
  retry: ['ready'],
  assign: ['ready'],
  redeliver: ['delivery_failed'],
  cancel: ['ready', 'delivery_failed'],
};

/** Đơn chưa có shipper nhận thì mới "Mời lại" được. */
export function checkStaffAction(order: Record<string, unknown> | null, req: StaffRequest): void {
  if (!order || order.channel !== 'online') throw new OrderRuleError(404, 'order_missing', 'Không tìm thấy đơn');
  const status = String(order.status);
  if (!STAFF_FROM[req.action].includes(status)) {
    throw new OrderRuleError(409, 'wrong_status', 'Đơn vừa được cập nhật, vui lòng xem lại');
  }
  if (req.action === 'retry' && obj(order.delivery).shipper) {
    throw new OrderRuleError(409, 'has_shipper', 'Đơn đã có shipper nhận – dùng "Đổi shipper"');
  }
}

export interface StaffResult {
  order_id: string;
  status: string;
  dispatch?: DispatchResult;
}

export async function handleStaffDispatch(
  db: Firestore,
  claims: FirebaseUserClaims,
  orderId: string,
  body: unknown,
  now = new Date(),
  defer: Defer = (p) => p,
): Promise<StaffResult> {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(orderId)) {
    throw new OrderRuleError(400, 'invalid_request', 'Mã đơn không hợp lệ');
  }
  const req = parseStaffRequest(body);
  const me = await db.get(`users/${claims.uid}`);
  const role = me?.data.role;
  if ((role !== 'staff' && role !== 'admin') || me?.data.is_active !== true) {
    throw new OrderRuleError(403, 'forbidden', 'Chỉ nhân viên/admin được thao tác');
  }
  const by = { id: claims.uid, name: String(me.data.name ?? ''), role: String(role) };
  const path = `orders/${orderId}`;
  const history = (status: string) => arrayAppend('status_history', { status, at: new Ts(now), by });

  // Gán thẳng: đọc trước shipper được chọn.
  let target: { id: string; name: string; phone: string } | null = null;
  if (req.action === 'assign') {
    const u = await db.get(`users/${req.shipperId}`);
    if (u?.data.role !== 'shipper' || u.data.is_active !== true) {
      throw new OrderRuleError(404, 'shipper_missing', 'Không tìm thấy shipper');
    }
    target = { id: u.id, name: String(u.data.name ?? ''), phone: String(u.data.phone ?? '') };
  }
  const settings = req.action === 'redeliver' ? await db.get('settings/shop') : null;

  const status = await db.runOptimistic(async (tx) => {
    const order = await db.get(path, tx);
    checkStaffAction(order?.data ?? null, req);
    const o = order!.data;
    const base = { updateTime: order!.updateTime };
    const writes: FsWrite[] = [];

    switch (req.action) {
      case 'ready':
        writes.push(
          patchWrite(
            order!.name,
            { status: 'ready', dispatch: emptyDispatch() },
            { ...base, transforms: [history('ready'), serverTime('updated_at')] },
          ),
        );
        return { writes, result: 'ready' };

      case 'retry': {
        writes.push(...(await releaseOfferWrites(db, order!, tx, now)));
        const d = { ...emptyDispatch(), attempts: Number(obj(o.dispatch).attempts ?? 0) };
        writes.unshift(
          patchWrite(order!.name, { dispatch: d }, { ...base, transforms: [serverTime('updated_at')] }),
        );
        return { writes, result: 'ready' };
      }

      case 'assign': {
        if (obj(o.delivery).shipper && obj(obj(o.delivery).shipper).id === target!.id) {
          throw new OrderRuleError(409, 'same_shipper', 'Đơn đang do shipper này giữ');
        }
        const st = await db.get(`shipper_status/${target!.id}`, tx);
        if (!st || st.data.on_shift !== true) {
          throw new OrderRuleError(409, 'not_on_shift', 'Shipper này không trong ca');
        }
        const offerWrites = await releaseOfferWrites(db, order!, tx, now);
        const holderWrites = await releaseHolderWrites(db, order!, tx, target!.id);
        const pending = obj(st.data.pending_offer);
        const d = obj(o.dispatch);
        writes.push(
          patchWrite(
            order!.name,
            {
              dispatch: {
                ...emptyDispatch(),
                ...d,
                state: 'assigned',
                offered_to: null,
                offer_id: null,
                manual_by: { id: by.id, name: by.name },
              },
              'delivery.shipper': target,
              'delivery.assigned_at': new Ts(now),
            },
            { ...base, transforms: [serverTime('updated_at')] },
          ),
          // Lời mời đang treo của chính người được gán (cho đơn này) thì bỏ luôn – đã release ở trên.
          ...offerWrites.filter((w) => w.update.name !== st.name),
          ...holderWrites,
          patchWrite(
            st.name,
            pending.order_id === orderId ? { pending_offer: null } : {},
            { updateTime: st.updateTime, transforms: [arrayAppend('active_order_ids', orderId)] },
          ),
        );
        return { writes, result: 'ready' };
      }

      case 'redeliver': {
        const shop = parseShopSettings(settings?.data ?? null);
        const fee = Number(obj(o.delivery).fee ?? 0);
        const extra = shop.shippingFee.enabled && fee > 0 ? fee : 0;
        const flat: Record<string, unknown> = {
          status: 'ready',
          dispatch: emptyDispatch(),
          'delivery.shipper': null,
          'delivery.assigned_at': null,
          'delivery.picked_up_at': null,
          'delivery.arrived_at': null,
          'delivery.call_attempts': [],
        };
        const transforms = [history('ready'), serverTime('updated_at')];
        if (extra > 0) {
          flat.total = Number(o.total ?? 0) + extra;
          transforms.push(
            arrayAppend('extra_fees', { reason: 'redelivery', amount: extra, at: new Ts(now), by }),
          );
        }
        writes.push(patchWrite(order!.name, flat, { ...base, transforms }));
        return { writes, result: 'ready' };
      }

      case 'cancel': {
        const fromReady = o.status === 'ready';
        const paid = o.payment_status === 'paid';
        const refund = obj(o.refund);
        const owed = refund.required === true && refund.done !== true ? Number(refund.amount ?? 0) : 0;
        const flat: Record<string, unknown> = {
          status: 'cancelled',
          cancelled_by: by,
          cancel_reason: req.reason,
        };
        // Hủy lúc Sẵn sàng: hoàn tiền nếu đã trả (O17). Giao thất bại rồi hủy: không hoàn (O21).
        if (fromReady && paid) {
          flat.payment_status = 'refunded';
          flat.refund = { required: true, amount: owed + Number(o.total ?? 0), done: false };
        }
        writes.push(
          patchWrite(order!.name, flat, {
            ...base,
            transforms: [history('cancelled'), serverTime('cancelled_at'), serverTime('updated_at')],
          }),
        );
        if (fromReady) {
          writes.push(...(await releaseOfferWrites(db, order!, tx, now)));
          writes.push(...(await releaseHolderWrites(db, order!, tx)));
        }
        return { writes, result: 'cancelled' };
      }
    }
  });

  const result: StaffResult = { order_id: orderId, status };
  if (req.action === 'ready' || req.action === 'retry' || req.action === 'redeliver') {
    // Trả lời NV ngay; việc tìm shipper chạy nốt trong nền (app thấy qua Firestore).
    await defer(offerNextSafe(db, orderId, now));
  }
  return result;
}

