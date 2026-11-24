// Logic thuần (không gọi mạng) cho việc tạo đơn online – để unit test.
// Mọi tiền là số nguyên VND. Giờ tính theo Việt Nam (UTC+7) vì Worker chạy UTC.

export const VN_OFFSET_MS = 7 * 3600_000;
export const MAX_QTY_PER_ITEM = 50;
export const MAX_ITEMS = 30;
export const MAX_NOTE = 200;

// ------------------------------------------------------------ Giờ Việt Nam

export function vnParts(d: Date) {
  const v = new Date(d.getTime() + VN_OFFSET_MS);
  return {
    year: v.getUTCFullYear(),
    month: v.getUTCMonth() + 1,
    day: v.getUTCDate(),
    hour: v.getUTCHours(),
    minute: v.getUTCMinutes(),
  };
}

const p2 = (n: number) => String(n).padStart(2, '0');

/** "ON-231126-005" (O13). */
export function onlineOrderCode(seq: number, d: Date): string {
  const t = vnParts(d);
  return `ON-${p2(t.day)}${p2(t.month)}${String(t.year).slice(2)}-${String(seq).padStart(3, '0')}`;
}

/** Bộ đếm theo ngày: counters/online_yyyyMMdd. */
export function onlineCounterId(d: Date): string {
  const t = vnParts(d);
  return `online_${t.year}${p2(t.month)}${p2(t.day)}`;
}

function minutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

/** Giống ShopSettings.isWithinHours bên app (hỗ trợ qua nửa đêm). */
export function isWithinHours(open: string, close: string, now: Date): boolean {
  const o = minutes(open);
  const c = minutes(close);
  const t = vnParts(now);
  const cur = t.hour * 60 + t.minute;
  if (o === c) return true;
  if (o < c) return cur >= o && cur < c;
  return cur >= o || cur < c;
}

// ------------------------------------------------------------ Cài đặt quán

export interface ShopSettings {
  name: string;
  location: { lat: number; lng: number } | null;
  openTime: string;
  closeTime: string;
  onlinePaused: boolean;
  maxDeliveryKm: number;
  minOrderValue: number;
  shippingFee: { enabled: boolean; baseKm: number; baseFee: number; perKm: number };
  paymentTimeoutMin: number;
  requireShipperOnShift: boolean;
}

const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d);
const str = (v: unknown, d: string) => (typeof v === 'string' ? v : d);
const bool = (v: unknown, d: boolean) => (typeof v === 'boolean' ? v : d);
const obj = (v: unknown) => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {});

/** Đọc settings/shop với giá trị mặc định giống app (models/shop_settings.dart). */
export function parseShopSettings(raw: Record<string, unknown> | null): ShopSettings {
  const r = raw ?? {};
  const loc = obj(r.location);
  const fee = obj(r.shipping_fee);
  return {
    name: str(r.name, 'Meow Coffee'),
    location:
      typeof loc.lat === 'number' && typeof loc.lng === 'number'
        ? { lat: loc.lat, lng: loc.lng }
        : null,
    openTime: str(r.open_time, '07:00'),
    closeTime: str(r.close_time, '22:00'),
    onlinePaused: bool(r.online_paused, false),
    maxDeliveryKm: num(r.max_delivery_km, 7),
    minOrderValue: Math.round(num(r.min_order_value, 50000)),
    shippingFee: {
      enabled: bool(fee.enabled, false),
      baseKm: num(fee.base_km, 3),
      baseFee: Math.round(num(fee.base_fee, 15000)),
      perKm: Math.round(num(fee.per_km, 5000)),
    },
    paymentTimeoutMin: Math.round(num(r.payment_timeout_min, 2)),
    requireShipperOnShift: bool(r.require_shipper_on_shift, false),
  };
}

/** Giống ShippingFeeConfig.feeFor bên app. Giai đoạn 1 tắt → 0 (O9). */
export function shippingFee(cfg: ShopSettings['shippingFee'], km: number): number {
  if (!cfg.enabled) return 0;
  if (km <= cfg.baseKm) return cfg.baseFee;
  return cfg.baseFee + Math.ceil(km - cfg.baseKm) * cfg.perKm;
}

// ------------------------------------------------------------ Yêu cầu

export interface OrderRequestItem {
  product_id: string;
  size: string;
  quantity: number;
  note: string;
}

export interface OrderRequest {
  items: OrderRequestItem[];
  address_id: string;
  payment_method: 'cash' | 'vietqr';
  note: string;
}

export class OrderRuleError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const bad = (message: string) => new OrderRuleError(400, 'invalid_request', message);

/** Kiểm dạng dữ liệu app gửi lên. Giá/tên món KHÔNG lấy từ app. */
export function parseOrderRequest(body: unknown): OrderRequest {
  const b = obj(body);
  if (!Array.isArray(b.items) || b.items.length === 0) throw bad('Giỏ hàng trống');
  if (b.items.length > MAX_ITEMS) throw bad(`Tối đa ${MAX_ITEMS} dòng món mỗi đơn`);
  const items = b.items.map((raw) => {
    const i = obj(raw);
    const qty = i.quantity;
    if (typeof i.product_id !== 'string' || i.product_id.length === 0) throw bad('Thiếu mã món');
    if (typeof i.size !== 'string' || i.size.length === 0) throw bad('Thiếu size');
    if (typeof qty !== 'number' || !Number.isInteger(qty) || qty < 1 || qty > MAX_QTY_PER_ITEM) {
      throw bad(`Số lượng mỗi món từ 1 đến ${MAX_QTY_PER_ITEM}`);
    }
    const note = typeof i.note === 'string' ? i.note.trim() : '';
    if (note.length > MAX_NOTE) throw bad('Ghi chú món quá dài');
    return { product_id: i.product_id, size: i.size, quantity: qty, note };
  });
  if (typeof b.address_id !== 'string' || b.address_id.length === 0) {
    throw bad('Vui lòng chọn địa chỉ giao hàng');
  }
  if (b.payment_method !== 'cash' && b.payment_method !== 'vietqr') {
    throw bad('Phương thức thanh toán không hợp lệ');
  }
  const note = typeof b.note === 'string' ? b.note.trim() : '';
  if (note.length > MAX_NOTE) throw bad('Ghi chú đơn quá dài');
  return { items, address_id: b.address_id, payment_method: b.payment_method, note };
}

// ------------------------------------------------------------ Kiểm tra & dựng đơn

export interface CustomerInfo {
  uid: string;
  name: string;
  phone: string;
  role: string;
  isActive: boolean;
  /** SĐT đã xác minh (token phone_number trùng phone_e164) hoặc email đã xác minh. */
  verified: boolean;
}

export interface AddressInfo {
  receiverName: string;
  receiverPhone: string;
  street: string;
  ward: { code: number; name: string };
  province: { code: number; name: string };
  note: string;
  location: { lat: number; lng: number };
}

export interface ProductInfo {
  id: string;
  name: string;
  category: string;
  prices: Record<string, number>;
  isAvailable: boolean;
}

export function parseProduct(id: string, raw: Record<string, unknown>): ProductInfo {
  const price = raw.price;
  const prices: Record<string, number> = {};
  if (price && typeof price === 'object') {
    for (const [k, v] of Object.entries(price as Record<string, unknown>)) {
      if (typeof v === 'number') prices[k] = Math.round(v);
    }
  } else if (typeof price === 'number') {
    prices.default = Math.round(price);
  }
  return {
    id,
    name: str(raw.name, ''),
    category: str(raw.category, ''),
    prices,
    isAvailable: bool(raw.is_available, true),
  };
}

export function parseAddress(raw: Record<string, unknown> | null): AddressInfo | null {
  if (!raw) return null;
  const loc = obj(raw.location);
  const ward = obj(raw.ward);
  const province = obj(raw.province);
  if (typeof loc.lat !== 'number' || typeof loc.lng !== 'number') return null;
  return {
    receiverName: str(raw.receiver_name, ''),
    receiverPhone: str(raw.receiver_phone, ''),
    street: str(raw.street, ''),
    ward: { code: num(ward.code, 0), name: str(ward.name, '') },
    province: { code: num(province.code, 0), name: str(province.name, '') },
    note: str(raw.note, ''),
    location: { lat: loc.lat, lng: loc.lng },
  };
}

export interface OrderItemSnapshot {
  product_id: string;
  name: string;
  category: string;
  size: string;
  unit_price: number;
  quantity: number;
  note: string;
  line_total: number;
}

/** Kiểm điều kiện mở cửa / tài khoản (trước khi đọc món, tính km). */
export function checkCanOrder(args: {
  customer: CustomerInfo | null;
  settings: ShopSettings;
  now: Date;
  shippersOnShift: number | null;
}): void {
  const { customer, settings, now, shippersOnShift } = args;
  if (!customer || customer.role !== 'customer') {
    throw new OrderRuleError(403, 'not_customer', 'Chỉ tài khoản khách hàng được đặt đơn online');
  }
  if (!customer.isActive) throw new OrderRuleError(403, 'locked', 'Tài khoản đã bị khóa');
  if (!customer.verified) {
    throw new OrderRuleError(403, 'not_verified', 'Vui lòng xác minh số điện thoại hoặc email trước khi đặt đơn');
  }
  if (!settings.location) {
    throw new OrderRuleError(409, 'shop_no_location', 'Quán chưa thiết lập vị trí, tạm chưa nhận đơn online');
  }
  if (settings.onlinePaused) {
    throw new OrderRuleError(409, 'paused', 'Quán đang tạm ngưng nhận đơn online');
  }
  if (!isWithinHours(settings.openTime, settings.closeTime, now)) {
    throw new OrderRuleError(
      409,
      'closed',
      `Quán nhận đơn online từ ${settings.openTime} đến ${settings.closeTime}`,
    );
  }
  if (settings.requireShipperOnShift && (shippersOnShift ?? 0) === 0) {
    throw new OrderRuleError(409, 'no_shipper', 'Hiện chưa có shipper, vui lòng quay lại sau');
  }
}

/** Chụp giá món từ server; món hết/không có size → lỗi. */
export function priceItems(
  items: OrderRequestItem[],
  products: Map<string, ProductInfo>,
): { items: OrderItemSnapshot[]; subtotal: number } {
  const out: OrderItemSnapshot[] = [];
  for (const i of items) {
    const p = products.get(i.product_id);
    if (!p) throw new OrderRuleError(409, 'product_missing', 'Có món không còn trong thực đơn');
    if (!p.isAvailable) {
      throw new OrderRuleError(409, 'sold_out', `${p.name} đang hết hàng, vui lòng bỏ khỏi giỏ`);
    }
    const unit = p.prices[i.size];
    if (typeof unit !== 'number') {
      throw new OrderRuleError(409, 'bad_size', `${p.name} không có size ${i.size}`);
    }
    out.push({
      product_id: p.id,
      name: p.name,
      category: p.category,
      size: i.size,
      unit_price: unit,
      quantity: i.quantity,
      note: i.note,
      line_total: unit * i.quantity,
    });
  }
  return { items: out, subtotal: out.reduce((s, i) => s + i.line_total, 0) };
}

/** Đơn tối thiểu và bán kính (O10) – báo rõ lý do. */
export function checkDeliveryLimits(subtotal: number, distanceKm: number, s: ShopSettings): void {
  if (s.minOrderValue > 0 && subtotal < s.minOrderValue) {
    const need = (s.minOrderValue - subtotal).toLocaleString('vi-VN');
    throw new OrderRuleError(409, 'below_min', `Mua thêm ${need}đ để được giao hàng`);
  }
  if (distanceKm > s.maxDeliveryKm) {
    throw new OrderRuleError(
      409,
      'too_far',
      `Địa chỉ cách quán ${distanceKm.toFixed(1)} km, quán chỉ giao trong ${s.maxDeliveryKm} km`,
    );
  }
}
