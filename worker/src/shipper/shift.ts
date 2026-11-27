// Ca làm việc của shipper (bước 8 – O20, O30).
//   POST /shipper/shift { action: 'start', location: {lat,lng} } | { action: 'end' }
//   cron mỗi phút: shipper không gửi GPS quá 15 phút và không giữ đơn → tự kết thúc ca.
// Vào/ra ca qua Worker để luôn ghi nhật ký ca (shipper_shifts) và cập nhật số
// shipper đang làm (settings/shop_live) – khách đọc số này để biết có đặt được không.
// Vị trí GPS trong ca thì app shipper ghi thẳng shipper_status (Rules kiểm).
import type { FirebaseUserClaims } from '../firebase/idToken';
import { encodeFields, Firestore, FirestoreError, Ts, type FsDoc, type FsWrite } from '../firebase/firestore';
import { OrderRuleError } from '../orders/rules';
import { hasLiveOffer } from '../dispatch/dispatch';

/** Không nhận GPS quá chừng này phút → tự kết thúc ca. */
export const SHIFT_STALE_MIN = 15;

export type ShiftEndReason = 'manual' | 'auto_no_gps';

export interface ShiftResult {
  on_shift: boolean;
  shift_id: string | null;
  shippers_on_shift: number;
}

interface LatLng {
  lat: number;
  lng: number;
}

/** Kiểm body của POST /shipper/shift (thuần, để test). */
export function parseShiftRequest(body: unknown): { action: 'start'; location: LatLng } | { action: 'end' } {
  const b = (body ?? {}) as { action?: unknown; location?: { lat?: unknown; lng?: unknown } };
  if (b.action === 'end') return { action: 'end' };
  if (b.action !== 'start') {
    throw new OrderRuleError(400, 'invalid_request', 'Thao tác không hợp lệ');
  }
  const lat = b.location?.lat;
  const lng = b.location?.lng;
  if (
    typeof lat !== 'number' || typeof lng !== 'number' ||
    !Number.isFinite(lat) || !Number.isFinite(lng) ||
    Math.abs(lat) > 90 || Math.abs(lng) > 180
  ) {
    throw new OrderRuleError(400, 'location_required', 'Cần bật định vị để bắt đầu ca');
  }
  return { action: 'start', location: { lat, lng } };
}

function activeOrders(status: Record<string, unknown> | undefined): string[] {
  const ids = status?.active_order_ids;
  return Array.isArray(ids) ? ids.map(String) : [];
}

/** Shipper đang trong ca nhưng mất GPS quá lâu và không giữ đơn (thuần, để test). */
export function isShiftStale(status: Record<string, unknown>, now: Date): boolean {
  if (status.on_shift !== true || activeOrders(status).length > 0) return false;
  const at = status.location_updated_at ?? status.shift_started_at;
  if (!(at instanceof Date)) return true;
  return now.getTime() - at.getTime() > SHIFT_STALE_MIN * 60_000;
}

/** Đếm lại shipper đang trong ca và ghi vào settings/shop_live. */
export async function refreshShopLive(db: Firestore): Promise<number> {
  const n = await db.countWhere('shipper_status', 'on_shift', true);
  await db.commit([
    {
      update: { name: db.docName('settings/shop_live'), fields: encodeFields({ shippers_on_shift: n }) },
      updateMask: { fieldPaths: ['shippers_on_shift'] },
      updateTransforms: [{ fieldPath: 'updated_at', setToServerValue: 'REQUEST_TIME' }],
    },
  ]);
  return n;
}

/** Ghi kết thúc ca: shipper_status + nhật ký ca (một commit, chỉ khi status chưa đổi). */
function endShiftWrites(db: Firestore, status: FsDoc, reason: ShiftEndReason, now: Date): FsWrite[] {
  const writes: FsWrite[] = [
    {
      update: { name: status.name, fields: encodeFields({ on_shift: false, shift_id: null }) },
      updateMask: { fieldPaths: ['on_shift', 'shift_id'] },
      currentDocument: status.updateTime ? { updateTime: status.updateTime } : undefined,
      updateTransforms: [{ fieldPath: 'shift_ended_at', setToServerValue: 'REQUEST_TIME' }],
    },
  ];
  const shiftId = typeof status.data.shift_id === 'string' ? status.data.shift_id : '';
  if (shiftId) {
    const started = status.data.shift_started_at;
    const lastGps = status.data.location_updated_at;
    const fields = {
      end_reason: reason,
      last_location_at: lastGps instanceof Date ? new Ts(lastGps) : null,
      duration_min:
        started instanceof Date ? Math.max(0, Math.round((now.getTime() - started.getTime()) / 60_000)) : null,
    };
    writes.push({
      update: { name: db.docName(`shipper_shifts/${shiftId}`), fields: encodeFields(fields) },
      updateMask: { fieldPaths: Object.keys(fields) },
      updateTransforms: [{ fieldPath: 'ended_at', setToServerValue: 'REQUEST_TIME' }],
    });
  }
  return writes;
}

export async function handleShift(
  db: Firestore,
  claims: FirebaseUserClaims,
  body: unknown,
  now = new Date(),
): Promise<ShiftResult> {
  const req = parseShiftRequest(body);
  const statusPath = `shipper_status/${claims.uid}`;
  const [userDoc, status] = await db.getMany([`users/${claims.uid}`, statusPath]);
  const u = userDoc?.data;
  if (!u || u.role !== 'shipper' || u.is_active !== true) {
    throw new OrderRuleError(403, 'not_shipper', 'Chỉ tài khoản shipper mới vào ca được');
  }
  const onShift = status?.data.on_shift === true;

  if (req.action === 'start') {
    if (onShift) {
      return {
        on_shift: true,
        shift_id: String(status!.data.shift_id ?? ''),
        shippers_on_shift: await refreshShopLive(db),
      };
    }
    const shipper = { id: claims.uid, name: String(u.name ?? ''), phone: String(u.phone ?? '') };
    const shiftId = `${claims.uid}_${now.getTime()}`;
    const statusFields = {
      on_shift: true,
      shift_id: shiftId,
      shipper,
      location: req.location,
      location_updated_at: new Ts(now),
      shift_started_at: new Ts(now),
      shift_declines: 0,
      pending_offer: null,
      active_order_ids: activeOrders(status?.data),
    };
    await db.commit([
      {
        update: {
          name: db.docName(`shipper_shifts/${shiftId}`),
          fields: encodeFields({
            shipper,
            started_at: new Ts(now),
            start_location: req.location,
            ended_at: null,
            end_reason: null,
          }),
        },
        currentDocument: { exists: false },
      },
      {
        update: { name: db.docName(statusPath), fields: encodeFields(statusFields) },
        updateMask: { fieldPaths: Object.keys(statusFields) },
        // Không vào ca 2 lần nếu 2 máy bấm cùng lúc.
        currentDocument: status
          ? status.updateTime
            ? { updateTime: status.updateTime }
            : { exists: true }
          : { exists: false },
      },
    ]);
    return { on_shift: true, shift_id: shiftId, shippers_on_shift: await refreshShopLive(db) };
  }

  // action === 'end'
  if (!onShift) {
    return { on_shift: false, shift_id: null, shippers_on_shift: await refreshShopLive(db) };
  }
  if (activeOrders(status!.data).length > 0) {
    throw new OrderRuleError(
      409,
      'has_orders',
      'Bạn còn đơn đang giữ – giao xong (hoặc nhờ quán đổi shipper) mới kết thúc ca',
    );
  }
  if (hasLiveOffer(status!.data, now)) {
    throw new OrderRuleError(409, 'has_offer', 'Bạn đang có lời mời giao đơn – hãy trả lời trước');
  }
  await db.commit(endShiftWrites(db, status!, 'manual', now));
  return { on_shift: false, shift_id: null, shippers_on_shift: await refreshShopLive(db) };
}

/** Cron: tự kết thúc ca của shipper mất GPS quá lâu. Trả về số ca đã kết thúc. */
export async function endStaleShifts(db: Firestore, now = new Date()): Promise<number> {
  const onShift = await db.findWhere('shipper_status', 'on_shift', true, 200);
  let ended = 0;
  for (const status of onShift) {
    if (!isShiftStale(status.data, now)) continue;
    try {
      await db.commit(endShiftWrites(db, status, 'auto_no_gps', now));
      ended++;
    } catch (e) {
      // Shipper vừa gửi GPS / đổi trạng thái trong lúc chạy → lần sau xét lại.
      if (e instanceof FirestoreError && (e.status === 409 || e.code === 'FAILED_PRECONDITION')) continue;
      throw e;
    }
  }
  if (ended > 0) await refreshShopLive(db);
  return ended;
}
