// POST /orders – tạo đơn online cho khách (docs/ke-hoach-ban-online.md mục 3.2).
import type { FirebaseUserClaims } from '../firebase/idToken';
import { encodeFields, Firestore, Ts, type FsWrite } from '../firebase/firestore';
import { roadDistanceKm } from './distance';
import {
  checkCanOrder,
  checkDeliveryLimits,
  OrderRuleError,
  onlineCounterId,
  onlineOrderCode,
  parseAddress,
  parseOrderRequest,
  parseProduct,
  parseShopSettings,
  priceItems,
  shippingFee,
  type CustomerInfo,
  type ProductInfo,
} from './rules';

export interface CreateOrderResult {
  order_id: string;
  order_code: string;
  status: 'pending' | 'awaiting_payment';
  total: number;
  payment_method: 'cash' | 'vietqr';
  payment_expires_at: string | null;
  distance_km: number;
}

export async function createOrder(
  db: Firestore,
  claims: FirebaseUserClaims,
  body: unknown,
  now = new Date(),
): Promise<CreateOrderResult> {
  const req = parseOrderRequest(body);

  // 1–2. Tài khoản + cài đặt quán (đọc song song).
  const [userDoc, settingsDoc] = await db.getMany([`users/${claims.uid}`, 'settings/shop']);
  const settings = parseShopSettings(settingsDoc?.data ?? null);
  const u = userDoc?.data;
  const phoneE164 = typeof u?.phone_e164 === 'string' ? u.phone_e164 : '';
  const customer: CustomerInfo | null = u
    ? {
        uid: claims.uid,
        name: String(u.name ?? ''),
        phone: String(u.phone ?? ''),
        role: String(u.role ?? ''),
        isActive: u.is_active === true,
        // Tin token của Firebase Auth, không tin cờ trong hồ sơ.
        verified:
          (!!claims.phoneNumber && claims.phoneNumber === phoneE164) || claims.emailVerified,
      }
    : null;
  const shippersOnShift = settings.requireShipperOnShift
    ? await db.countWhere('shipper_status', 'on_shift', true)
    : null;
  checkCanOrder({ customer, settings, now, shippersOnShift });

  // 3. Địa chỉ lấy từ sổ địa chỉ của chính khách (không tin địa chỉ app gửi).
  const addressDoc = await db.get(`users/${claims.uid}/addresses/${req.address_id}`);
  const address = parseAddress(addressDoc?.data ?? null);
  if (!address) {
    throw new OrderRuleError(400, 'address_missing', 'Không tìm thấy địa chỉ giao hàng');
  }

  // 4–5. Giá món từ server.
  const productIds = [...new Set(req.items.map((i) => i.product_id))];
  const productDocs = await db.getMany(productIds.map((id) => `products/${id}`));
  const products = new Map<string, ProductInfo>();
  productDocs.forEach((d) => d && products.set(d.id, parseProduct(d.id, d.data)));
  const { items, subtotal } = priceItems(req.items, products);

  // 6. Quãng đường, bán kính, phí ship.
  const distance = await roadDistanceKm(settings.location!, address.location);
  checkDeliveryLimits(subtotal, distance.km, settings);
  const fee = shippingFee(settings.shippingFee, distance.km);
  const discount = 0;
  const total = subtotal - discount + fee;

  const isVietQr = req.payment_method === 'vietqr';
  const status = isVietQr ? 'awaiting_payment' : 'pending';
  const expiresAt = isVietQr ? new Date(now.getTime() + settings.paymentTimeoutMin * 60_000) : null;
  const customerRef = { id: claims.uid, name: customer!.name, role: 'customer' };

  // 7. Transaction: tăng bộ đếm online theo ngày → sinh mã → ghi đơn.
  const orderId = crypto.randomUUID().replace(/-/g, '').slice(0, 20);
  const counterPath = `counters/${onlineCounterId(now)}`;
  const code = await db.runTransaction(async (tx) => {
    const counter = await db.get(counterPath, tx);
    const seq = Number(counter?.data.seq ?? 0) + 1;
    const orderCode = onlineOrderCode(seq, now);
    const order = {
      order_code: orderCode,
      channel: 'online',
      fulfillment: 'delivery',
      status,
      payment_method: req.payment_method,
      payment_status: 'unpaid',
      payment: isVietQr ? { amount_due: total, expires_at: new Ts(expiresAt!), tx_ids: [] } : null,
      customer: { id: claims.uid, name: customer!.name, phone: customer!.phone },
      delivery: {
        receiver_name: address.receiverName,
        receiver_phone: address.receiverPhone,
        address_text: [address.street, address.ward.name, address.province.name]
          .filter(Boolean)
          .join(', '),
        street: address.street,
        ward: address.ward,
        province: address.province,
        note: address.note,
        location: address.location,
        distance_km: Math.round(distance.km * 100) / 100,
        distance_source: distance.source,
        fee,
        shipper: null,
      },
      items,
      subtotal,
      discount,
      extra_fees: [],
      total,
      note: req.note,
      status_history: [{ status, at: new Ts(now), by: customerRef }],
    };
    const writes: FsWrite[] = [
      {
        update: { name: db.docName(counterPath), fields: encodeFields({ seq }) },
        currentDocument: counter ? { exists: true } : { exists: false },
      },
      {
        update: { name: db.docName(`orders/${orderId}`), fields: encodeFields(order) },
        currentDocument: { exists: false },
        updateTransforms: [{ fieldPath: 'created_at', setToServerValue: 'REQUEST_TIME' }],
      },
    ];
    return { writes, result: orderCode };
  });

  return {
    order_id: orderId,
    order_code: code,
    status,
    total,
    payment_method: req.payment_method,
    payment_expires_at: expiresAt?.toISOString() ?? null,
    distance_km: Math.round(distance.km * 10) / 10,
  };
}
