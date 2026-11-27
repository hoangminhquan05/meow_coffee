// Gán shipper: chấm điểm + ghép đơn (kế hoạch mục 6). Logic thuần – để test.
//   score = w_load × số đơn đang giữ + w_pickup × km tới quán
//         + w_detour × km phát sinh + w_today × số đơn đã giao hôm nay   (nhỏ hơn = tốt hơn)
import { haversineKm, ROAD_FACTOR } from '../orders/distance';
import { vnParts } from '../orders/rules';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface DispatchConfig {
  offerSeconds: number;
  maxOrdersPerShipper: number;
  batchRadiusKm: number;
  staleLocationMin: number;
  weights: { load: number; pickupKm: number; detourKm: number; today: number };
}

export interface FailureConfig {
  waitMinutes: number;
  minCallAttempts: number;
}

const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d);
const obj = (v: unknown) => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {});

/** settings/shop.dispatch – mặc định giống app (DispatchConfig). */
export function parseDispatchConfig(shop: Record<string, unknown> | null): DispatchConfig {
  const d = obj(shop?.dispatch);
  const w = obj(d.weights);
  return {
    offerSeconds: Math.max(15, Math.round(num(d.offer_seconds, 60))),
    maxOrdersPerShipper: Math.max(1, Math.round(num(d.max_orders_per_shipper, 3))),
    batchRadiusKm: num(d.batch_radius_km, 1.5),
    staleLocationMin: Math.round(num(d.stale_location_min, 10)),
    weights: {
      load: num(w.load, 3),
      pickupKm: num(w.pickup_km, 1),
      detourKm: num(w.detour_km, 2),
      today: num(w.today, 0.2),
    },
  };
}

/** settings/shop.delivery_failure (O29). */
export function parseFailureConfig(shop: Record<string, unknown> | null): FailureConfig {
  const f = obj(shop?.delivery_failure);
  return {
    waitMinutes: Math.max(0, Math.round(num(f.wait_minutes, 10))),
    minCallAttempts: Math.max(0, Math.round(num(f.min_call_attempts, 2))),
  };
}

/** Km đường đi ước lượng giữa 2 điểm (chim bay × 1.3 – không gọi OSRM nhiều lần). */
export const roadKm = (a: LatLng, b: LatLng) => haversineKm(a, b) * ROAD_FACTOR;

function permutations<T>(xs: T[]): T[][] {
  if (xs.length <= 1) return [xs];
  return xs.flatMap((x, i) => permutations([...xs.slice(0, i), ...xs.slice(i + 1)]).map((p) => [x, ...p]));
}

/** Lộ trình ngắn nhất từ `start` đi qua mọi điểm (thử mọi hoán vị, ≤ 3 điểm). */
export function bestRouteKm(start: LatLng, stops: LatLng[]): number {
  if (stops.length === 0) return 0;
  let best = Infinity;
  for (const order of permutations(stops)) {
    let km = 0;
    let at = start;
    for (const s of order) {
      km += roadKm(at, s);
      at = s;
    }
    best = Math.min(best, km);
  }
  return best;
}

/** Thứ tự giao gợi ý cho các đơn đang giữ (trả về chỉ số theo mảng vào). */
export function bestRouteOrder(start: LatLng, stops: LatLng[]): number[] {
  if (stops.length === 0) return [];
  const idx = stops.map((_, i) => i);
  let best = idx;
  let bestKm = Infinity;
  for (const order of permutations(idx)) {
    let km = 0;
    let at = start;
    for (const i of order) {
      km += roadKm(at, stops[i]);
      at = stops[i];
    }
    if (km < bestKm) {
      bestKm = km;
      best = order;
    }
  }
  return best;
}

export interface Candidate {
  uid: string;
  name: string;
  phone: string;
  location: LatLng | null;
  locationAt: Date | null;
  /** Điểm giao của các đơn đang giữ. */
  heldDrops: LatLng[];
  /** Mọi đơn đang giữ còn ở quán (Sẵn sàng, chưa lấy hàng). */
  heldAllAtShop: boolean;
  deliveredToday: number;
}

export interface Scored {
  candidate: Candidate;
  score: number;
  pickupKm: number;
  detourKm: number;
}

/** Điểm của 1 shipper cho đơn giao tới `drop`; null nếu không nhận được đơn này. */
export function scoreCandidate(
  c: Candidate,
  shop: LatLng,
  drop: LatLng,
  cfg: DispatchConfig,
  now: Date,
): Scored | null {
  const held = c.heldDrops.length;
  if (held >= cfg.maxOrdersPerShipper) return null;
  if (held > 0) {
    // Ghép đơn: shipper chưa rời quán với các đơn kia và điểm giao gần mọi điểm đang giữ.
    if (!c.heldAllAtShop) return null;
    if (c.heldDrops.some((d) => haversineKm(d, drop) > cfg.batchRadiusKm)) return null;
  }
  const fresh =
    c.location !== null &&
    c.locationAt !== null &&
    now.getTime() - c.locationAt.getTime() <= cfg.staleLocationMin * 60_000;
  // Vị trí cũ: coi như ở quán nếu không giữ đơn, hoặc ở điểm giao cuối nếu đang giữ.
  const pos = fresh ? c.location! : held > 0 ? c.heldDrops[held - 1] : shop;
  const pickupKm = roadKm(pos, shop);
  const detourKm = bestRouteKm(shop, [...c.heldDrops, drop]) - bestRouteKm(shop, c.heldDrops);
  const w = cfg.weights;
  const score = w.load * held + w.pickupKm * pickupKm + w.detourKm * detourKm + w.today * c.deliveredToday;
  return { candidate: c, score: Math.round(score * 1000) / 1000, pickupKm, detourKm };
}

/** Shipper điểm nhỏ nhất (bằng điểm thì theo uid để kết quả ổn định). */
export function pickBest(
  cands: Candidate[],
  shop: LatLng,
  drop: LatLng,
  cfg: DispatchConfig,
  now: Date,
): Scored | null {
  let best: Scored | null = null;
  for (const c of cands) {
    const s = scoreCandidate(c, shop, drop, cfg, now);
    if (!s) continue;
    if (!best || s.score < best.score || (s.score === best.score && c.uid < best.candidate.uid)) best = s;
  }
  return best;
}

/** "20261127" theo giờ Việt Nam – khoá "hôm nay" cho thống kê shipper. */
export function vnDayKey(d: Date): string {
  const t = vnParts(d);
  return `${t.year}${String(t.month).padStart(2, '0')}${String(t.day).padStart(2, '0')}`;
}

/** Số tiền shipper phải thu khi giao (COD: cả đơn; VietQR: phí giao lại – O33). */
export function amountToCollect(order: Record<string, unknown>): number {
  if (order.payment_method === 'cash') {
    return order.payment_status === 'paid' ? 0 : Math.max(0, Math.round(num(order.total, 0)));
  }
  const fees = Array.isArray(order.extra_fees) ? order.extra_fees : [];
  return fees.reduce((s: number, f) => s + Math.max(0, Math.round(num(obj(f).amount, 0))), 0);
}

/** Lý do chưa được bấm "Giao không thành công" (O29); null = được. */
export function failureBlocker(
  delivery: Record<string, unknown>,
  cfg: FailureConfig,
  now: Date,
): string | null {
  const arrived = delivery.arrived_at;
  if (!(arrived instanceof Date)) return 'Bạn cần bấm "Đã đến nơi" trước';
  const waited = (now.getTime() - arrived.getTime()) / 60_000;
  if (waited < cfg.waitMinutes) {
    return `Cần chờ đủ ${cfg.waitMinutes} phút sau khi đến nơi (còn ${Math.ceil(cfg.waitMinutes - waited)} phút)`;
  }
  const calls = Array.isArray(delivery.call_attempts) ? delivery.call_attempts.length : 0;
  if (calls < cfg.minCallAttempts) {
    return `Cần gọi cho khách ít nhất ${cfg.minCallAttempts} lần (đã gọi ${calls})`;
  }
  return null;
}

/** Cảnh báo từ chối trong ca (O35): lần 2 cảnh báo, từ lần 3 mỗi lần nhắc + báo admin. */
export function declineWarning(shiftDeclines: number): { message: string | null; notifyAdmin: boolean } {
  if (shiftDeclines < 2) return { message: null, notifyAdmin: false };
  return {
    message:
      shiftDeclines === 2
        ? 'Bạn đã từ chối/bỏ lỡ 2 đơn trong ca. Hãy nhận đơn để không ảnh hưởng đánh giá.'
        : `Bạn đã từ chối/bỏ lỡ ${shiftDeclines} đơn trong ca. Quản lý đã được thông báo.`,
    notifyAdmin: shiftDeclines >= 3,
  };
}
