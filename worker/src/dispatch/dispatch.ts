// Gán shipper cho đơn "Sẵn sàng" (bước 9 – O35, kế hoạch mục 6).
//   offerNext       chọn shipper điểm thấp nhất → lời mời 60s (orders.dispatch + shipper_status.pending_offer)
//   respondOffer    shipper Nhận / Từ chối / hết giờ (app báo khi đếm ngược xong)
//   runDispatchCron mỗi phút: lời mời quá hạn → tính "hết giờ", mời người tiếp; đơn chưa có shipper → mời lại
// Mỗi lời mời ghi một dòng dispatch_offers (cho màn Hiệu suất shipper – O36).
import type { FirebaseUserClaims } from '../firebase/idToken';
import {
  arrayAppend,
  arrayRemove,
  Firestore,
  FirestoreError,
  increment,
  patchWrite,
  serverTime,
  Ts,
  type FsDoc,
  type FsWrite,
} from '../firebase/firestore';
import { OrderRuleError } from '../orders/rules';
import {
  declineWarning,
  parseDispatchConfig,
  pickBest,
  vnDayKey,
  type Candidate,
  type LatLng,
} from './score';

/** Cho app gửi "hết giờ" sớm vài giây (lệch đồng hồ) và vẫn nhận lời mời trễ vài giây. */
const CLOCK_SLACK_MS = 5_000;

export type DispatchState = 'searching' | 'offering' | 'assigned' | 'no_shipper';

export interface DispatchResult {
  state: DispatchState | 'skipped';
  shipper?: { id: string; name: string };
  expires_at?: string;
}

const obj = (v: unknown) => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {});
const strs = (v: unknown) => (Array.isArray(v) ? v.map(String) : []);
const latLng = (v: unknown): LatLng | null => {
  const o = obj(v);
  return typeof o.lat === 'number' && typeof o.lng === 'number' ? { lat: o.lat, lng: o.lng } : null;
};

export const isConflict = (e: unknown) =>
  e instanceof FirestoreError &&
  (e.status === 409 || e.code === 'FAILED_PRECONDITION' || e.code === 'ABORTED');

/** Lời mời còn hạn trên shipper_status (thuần, để test). */
export function hasLiveOffer(status: Record<string, unknown>, now: Date, exceptOrderId?: string): boolean {
  const p = obj(status.pending_offer);
  if (!p.order_id || p.order_id === exceptOrderId) return false;
  return p.expires_at instanceof Date && p.expires_at.getTime() > now.getTime();
}

/** Đơn đang chờ shipper và không có lời mời còn hạn → cần mời (thuần, để test). */
export function needsDispatch(order: Record<string, unknown>, now: Date): 'offer' | 'timeout' | null {
  if (order.channel !== 'online' || order.status !== 'ready') return null;
  if (obj(order.delivery).shipper) return null;
  const d = obj(order.dispatch);
  if (d.state === 'offering') {
    const exp = d.expires_at;
    return exp instanceof Date && exp.getTime() > now.getTime() ? null : 'timeout';
  }
  return 'offer';
}

export function emptyDispatch(): Record<string, unknown> {
  return {
    state: 'searching',
    offered_to: null,
    offer_id: null,
    offered_at: null,
    expires_at: null,
    declined_by: [],
    attempts: 0,
    manual_by: null,
  };
}

interface Snapshot {
  shop: LatLng | null;
  cfg: ReturnType<typeof parseDispatchConfig>;
  candidates: Candidate[];
  statuses: Map<string, FsDoc>;
}

/** Đọc cài đặt + shipper trong ca + đơn họ đang giữ (ngoài transaction). */
async function loadSnapshot(db: Firestore, now: Date): Promise<Snapshot> {
  const [settings] = await db.getMany(['settings/shop']);
  const cfg = parseDispatchConfig(settings?.data ?? null);
  const shop = latLng(settings?.data.location);
  const onShift = await db.findWhere('shipper_status', 'on_shift', true, 200);
  const users = await db.getMany(onShift.map((s) => `users/${s.id}`));
  const heldIds = [...new Set(onShift.flatMap((s) => strs(s.data.active_order_ids)))];
  const held = await db.getMany(heldIds.map((id) => `orders/${id}`));
  const heldById = new Map(held.filter((d): d is FsDoc => d !== null).map((d) => [d.id, d.data]));
  const today = vnDayKey(now);

  const statuses = new Map<string, FsDoc>();
  const candidates: Candidate[] = [];
  onShift.forEach((s, i) => {
    const u = users[i]?.data;
    if (!u || u.role !== 'shipper' || u.is_active !== true) return;
    statuses.set(s.id, s);
    const heldOrders = strs(s.data.active_order_ids).map((id) => heldById.get(id));
    candidates.push({
      uid: s.id,
      name: String(u.name ?? ''),
      phone: String(u.phone ?? ''),
      location: latLng(s.data.location),
      locationAt: s.data.location_updated_at instanceof Date ? s.data.location_updated_at : null,
      heldDrops: heldOrders.map((o) => latLng(obj(o?.delivery).location)).filter((p): p is LatLng => !!p),
      heldAllAtShop: heldOrders.every((o) => o?.status === 'ready'),
      deliveredToday: s.data.stats_day === today ? Number(s.data.delivered_today ?? 0) : 0,
    });
  });
  return { shop, cfg, candidates, statuses };
}

/**
 * Mời shipper phù hợp nhất cho đơn đang "Sẵn sàng" và chưa có shipper.
 * Không còn ai → dispatch.state = 'no_shipper' (NV gán tay, cron thử lại mỗi phút).
 */
export async function offerNext(db: Firestore, orderId: string, now = new Date()): Promise<DispatchResult> {
  const snap = await loadSnapshot(db, now);
  const skip = new Set<string>();
  const orderPath = `orders/${orderId}`;

  for (let attempt = 0; attempt < 5; attempt++) {
    const result = await db.runOptimistic(async (tx) => {
      const order = await db.get(orderPath, tx);
      if (!order || needsDispatch(order.data, now) !== 'offer') {
        return { writes: [] as FsWrite[], result: { state: 'skipped' } as DispatchResult | { retry: string } };
      }
      const d = { ...emptyDispatch(), ...obj(order.data.dispatch) };
      const declined = strs(d.declined_by);
      const drop = latLng(obj(order.data.delivery).location);
      const shop = snap.shop ?? drop;
      const pool = snap.candidates.filter(
        (c) =>
          !declined.includes(c.uid) &&
          !skip.has(c.uid) &&
          !hasLiveOffer(snap.statuses.get(c.uid)!.data, now, orderId),
      );
      const best = drop && shop ? pickBest(pool, shop, drop, snap.cfg, now) : null;

      if (!best) {
        if (d.state === 'no_shipper') {
          return { writes: [], result: { state: 'no_shipper' } as DispatchResult };
        }
        return {
          writes: [
            patchWrite(
              order.name,
              { dispatch: { ...d, state: 'no_shipper', offered_to: null, offer_id: null } },
              { updateTime: order.updateTime, transforms: [serverTime('updated_at')] },
            ),
          ],
          result: { state: 'no_shipper' } as DispatchResult,
        };
      }

      // Đọc lại trạng thái của người được chọn trong transaction: vẫn trong ca, chưa có lời mời khác.
      const uid = best.candidate.uid;
      const status = await db.get(`shipper_status/${uid}`, tx);
      if (
        !status ||
        status.data.on_shift !== true ||
        hasLiveOffer(status.data, now, orderId) ||
        strs(status.data.active_order_ids).length >= snap.cfg.maxOrdersPerShipper
      ) {
        return { writes: [], result: { retry: uid } };
      }

      const attempts = Number(d.attempts ?? 0) + 1;
      const offerId = `${orderId}_${attempts}`;
      const expires = new Date(now.getTime() + snap.cfg.offerSeconds * 1000);
      const shipper = { id: uid, name: best.candidate.name };
      const code = String(order.data.order_code ?? '');
      return {
        writes: [
          patchWrite(
            order.name,
            {
              dispatch: {
                ...d,
                state: 'offering',
                offered_to: shipper,
                offer_id: offerId,
                offered_at: new Ts(now),
                expires_at: new Ts(expires),
                attempts,
              },
            },
            { updateTime: order.updateTime, transforms: [serverTime('updated_at')] },
          ),
          patchWrite(
            status.name,
            { pending_offer: { order_id: orderId, order_code: code, offer_id: offerId, expires_at: new Ts(expires) } },
            { updateTime: status.updateTime },
          ),
          patchWrite(
            db.docName(`dispatch_offers/${offerId}`),
            {
              order: { id: orderId, code },
              shipper,
              shift_id: status.data.shift_id ?? null,
              offered_at: new Ts(now),
              expires_at: new Ts(expires),
              responded_at: null,
              result: null,
              score: best.score,
              pickup_km: Math.round(best.pickupKm * 100) / 100,
              detour_km: Math.round(best.detourKm * 100) / 100,
              batched_with: best.candidate.heldDrops.length,
              manual: false,
            },
            { exists: false },
          ),
        ],
        result: { state: 'offering', shipper, expires_at: expires.toISOString() } as DispatchResult,
      };
    });
    if (!('retry' in result)) return result;
    skip.add(result.retry);
  }
  return { state: 'searching' };
}

/**
 * Việc làm tiếp sau khi đã trả lời app. Trong Worker: ctx.waitUntil (trả lời
 * ngay, việc vẫn chạy nốt); trong test: chờ luôn.
 */
export type Defer = (p: Promise<unknown>) => Promise<unknown> | void;

/** Mời tiếp sau một thao tác đã ghi xong: lỗi thì chỉ log – cron mời lại sau 1 phút. */
export async function offerNextSafe(db: Firestore, orderId: string, now: Date): Promise<DispatchResult> {
  try {
    return await offerNext(db, orderId, now);
  } catch (e) {
    console.error('offerNext failed', orderId, e instanceof FirestoreError ? `${e.status} ${e.message}` : e);
    return { state: 'searching' };
  }
}

/** Ghi kết quả từ chối / hết giờ của một lời mời (trong transaction đã đọc đơn + status). */
function closeOfferWrites(
  db: Firestore,
  order: FsDoc,
  status: FsDoc | null,
  result: 'declined' | 'timeout',
  now: Date,
): FsWrite[] {
  const d = { ...emptyDispatch(), ...obj(order.data.dispatch) };
  const offeredTo = obj(d.offered_to);
  const uid = String(offeredTo.id ?? '');
  const offerId = String(d.offer_id ?? '');
  const writes: FsWrite[] = [
    patchWrite(
      order.name,
      {
        dispatch: {
          ...d,
          state: 'searching',
          offered_to: null,
          offer_id: null,
          declined_by: [...new Set([...strs(d.declined_by), uid])],
        },
      },
      { updateTime: order.updateTime, transforms: [serverTime('updated_at')] },
    ),
  ];
  if (offerId) {
    writes.push(
      patchWrite(db.docName(`dispatch_offers/${offerId}`), { result, responded_at: new Ts(now) }, { exists: true }),
    );
  }
  const mine = status !== null && obj(status.data.pending_offer).offer_id === offerId;
  if (status && (mine || status.data.on_shift === true)) {
    writes.push(
      patchWrite(status.name, mine ? { pending_offer: null } : {}, {
        updateTime: status.updateTime,
        // Bộ đếm từ chối trong ca (O35) – chỉ tính khi shipper còn trong ca.
        transforms: status.data.on_shift === true ? [increment('shift_declines', 1)] : [],
      }),
    );
  }
  return writes;
}

export interface RespondResult {
  accepted: boolean;
  shift_declines: number;
  warning: string | null;
}

/** POST /dispatch/{orderId}/respond { offer_id, action: accept | decline | timeout } */
export async function respondOffer(
  db: Firestore,
  claims: FirebaseUserClaims,
  orderId: string,
  body: unknown,
  now = new Date(),
  defer: Defer = (p) => p,
): Promise<RespondResult> {
  const b = obj(body);
  const action = b.action;
  if (action !== 'accept' && action !== 'decline' && action !== 'timeout') {
    throw new OrderRuleError(400, 'invalid_request', 'Thao tác không hợp lệ');
  }
  const offerId = typeof b.offer_id === 'string' ? b.offer_id : '';
  const user = await db.get(`users/${claims.uid}`);
  if (user?.data.role !== 'shipper' || user.data.is_active !== true) {
    throw new OrderRuleError(403, 'not_shipper', 'Chỉ shipper mới trả lời lời mời');
  }

  const outcome = await db.runOptimistic(async (tx) => {
    const order = await db.get(`orders/${orderId}`, tx);
    const status = await db.get(`shipper_status/${claims.uid}`, tx);
    const d = obj(order?.data.dispatch);
    if (
      !order ||
      !status ||
      order.data.status !== 'ready' ||
      d.state !== 'offering' ||
      obj(d.offered_to).id !== claims.uid ||
      (offerId && d.offer_id !== offerId)
    ) {
      throw new OrderRuleError(409, 'offer_gone', 'Lời mời này không còn hiệu lực');
    }
    const expires = d.expires_at instanceof Date ? d.expires_at.getTime() : 0;
    const declines = Number(status.data.shift_declines ?? 0);

    if (action === 'accept') {
      if (now.getTime() > expires + CLOCK_SLACK_MS) {
        throw new OrderRuleError(409, 'offer_expired', 'Lời mời đã hết hạn');
      }
      if (status.data.on_shift !== true) {
        throw new OrderRuleError(409, 'not_on_shift', 'Bạn chưa vào ca');
      }
      const shipper = {
        id: claims.uid,
        name: String(user.data.name ?? ''),
        phone: String(user.data.phone ?? ''),
      };
      return {
        writes: [
          patchWrite(
            order.name,
            {
              'dispatch.state': 'assigned',
              'delivery.shipper': shipper,
              'delivery.assigned_at': new Ts(now),
            },
            { updateTime: order.updateTime, transforms: [serverTime('updated_at')] },
          ),
          patchWrite(
            status.name,
            { pending_offer: null },
            { updateTime: status.updateTime, transforms: [arrayAppend('active_order_ids', orderId)] },
          ),
          patchWrite(
            db.docName(`dispatch_offers/${d.offer_id}`),
            { result: 'accepted', responded_at: new Ts(now) },
            { exists: true },
          ),
        ],
        result: { accepted: true, shift_declines: declines, warning: null } as RespondResult,
      };
    }

    if (action === 'timeout' && now.getTime() < expires - CLOCK_SLACK_MS) {
      throw new OrderRuleError(409, 'offer_running', 'Lời mời vẫn còn thời gian');
    }
    const n = declines + 1;
    return {
      writes: closeOfferWrites(db, order, status, action === 'timeout' ? 'timeout' : 'declined', now),
      result: { accepted: false, shift_declines: n, warning: declineWarning(n).message } as RespondResult,
    };
  });

  // Mời người tiếp sau khi đã trả lời shipper (không bắt shipper chờ).
  if (!outcome.accepted) await defer(offerNextSafe(db, orderId, now));
  return outcome;
}

/** Cron: lời mời hết 60s → "hết giờ" (O35) rồi mời người tiếp; đơn chưa có shipper → thử mời lại. */
export async function runDispatchCron(db: Firestore, now = new Date()): Promise<{ timeouts: number; offers: number }> {
  const ready = await db.findWhere('orders', 'status', 'ready', 200);
  let timeouts = 0;
  let offers = 0;
  for (const o of ready) {
    const need = needsDispatch(o.data, now);
    if (!need) continue;
    try {
      if (need === 'timeout') {
        const closed = await db.runOptimistic(async (tx) => {
          const order = await db.get(`orders/${o.id}`, tx);
          if (!order || needsDispatch(order.data, now) !== 'timeout') {
            return { writes: [] as FsWrite[], result: false };
          }
          const uid = String(obj(obj(order.data.dispatch).offered_to).id ?? '');
          const status = uid ? await db.get(`shipper_status/${uid}`, tx) : null;
          return { writes: closeOfferWrites(db, order, status, 'timeout', now), result: true };
        });
        if (closed) timeouts++;
      }
      const r = await offerNext(db, o.id, now);
      if (r.state === 'offering') offers++;
    } catch (e) {
      // Có người vừa đổi đơn → phút sau xét lại.
      if (isConflict(e) || e instanceof OrderRuleError) continue;
      throw e;
    }
  }
  return { timeouts, offers };
}

/** Bỏ lời mời đang treo của đơn (khi NV gán tay / hủy): ghi log "cancelled", xoá pending_offer. */
export async function releaseOfferWrites(
  db: Firestore,
  order: FsDoc,
  tx: string,
  now: Date,
): Promise<FsWrite[]> {
  const d = obj(order.data.dispatch);
  if (d.state !== 'offering' || !d.offer_id) return [];
  const uid = String(obj(d.offered_to).id ?? '');
  const writes: FsWrite[] = [
    patchWrite(
      db.docName(`dispatch_offers/${d.offer_id}`),
      { result: 'cancelled', responded_at: new Ts(now) },
      { exists: true },
    ),
  ];
  const status = uid ? await db.get(`shipper_status/${uid}`, tx) : null;
  if (status && obj(status.data.pending_offer).offer_id === d.offer_id) {
    writes.push(patchWrite(status.name, { pending_offer: null }, { updateTime: status.updateTime }));
  }
  return writes;
}

/** Trả đơn khỏi danh sách đang giữ của shipper cũ (đơn chưa lấy hàng). */
export async function releaseHolderWrites(
  db: Firestore,
  order: FsDoc,
  tx: string,
  exceptUid?: string,
): Promise<FsWrite[]> {
  const holder = String(obj(obj(order.data.delivery).shipper).id ?? '');
  if (!holder || holder === exceptUid) return [];
  const status = await db.get(`shipper_status/${holder}`, tx);
  if (!status) return [];
  return [patchWrite(status.name, {}, { updateTime: status.updateTime, transforms: [arrayRemove('active_order_ids', order.id)] })];
}
