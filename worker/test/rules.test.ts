import { describe, expect, it } from 'vitest';
import { checkClaims } from '../src/firebase/idToken';
import { decodeFields, encodeFields, Ts } from '../src/firebase/firestore';
import { base64UrlDecode, base64UrlEncode } from '../src/firebase/jwt';
import { haversineKm } from '../src/orders/distance';
import {
  checkCanOrder,
  checkDeliveryLimits,
  isWithinHours,
  onlineCounterId,
  onlineOrderCode,
  OrderRuleError,
  parseOrderRequest,
  parseProduct,
  parseShopSettings,
  priceItems,
  shippingFee,
  type CustomerInfo,
} from '../src/orders/rules';

const settings = parseShopSettings({
  location: { lat: 21.0285, lng: 105.8542 },
  open_time: '07:00',
  close_time: '22:00',
  max_delivery_km: 7,
  min_order_value: 50000,
});
const customer: CustomerInfo = {
  uid: 'u1',
  name: 'Khách',
  phone: '0901 234 567',
  role: 'customer',
  isActive: true,
  verified: true,
};
// 10:00 giờ VN = 03:00 UTC.
const vn10am = new Date('2026-11-23T03:00:00Z');

function ruleCode(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    if (e instanceof OrderRuleError) return e.code;
    throw e;
  }
  return 'ok';
}

describe('Vietnam time helpers', () => {
  it('builds ON-ddMMyy-NNN and counter id in UTC+7', () => {
    // 23/11 18:30 UTC = 24/11 01:30 giờ VN → sang ngày mới.
    const d = new Date('2026-11-23T18:30:00Z');
    expect(onlineOrderCode(5, d)).toBe('ON-241126-005');
    expect(onlineCounterId(d)).toBe('online_20261124');
  });

  it('opening hours incl. overnight', () => {
    expect(isWithinHours('07:00', '22:00', vn10am)).toBe(true);
    expect(isWithinHours('07:00', '22:00', new Date('2026-11-23T23:30:00Z'))).toBe(false); // 06:30 VN
    expect(isWithinHours('18:00', '02:00', new Date('2026-11-23T17:00:00Z'))).toBe(true); // 00:00 VN
  });
});

describe('parseOrderRequest', () => {
  const ok = {
    items: [{ product_id: 'p1', size: 'M', quantity: 2, note: ' ít đá ' }],
    address_id: 'a1',
    payment_method: 'cash',
  };
  it('accepts a valid body and trims notes', () => {
    const r = parseOrderRequest(ok);
    expect(r.items[0].note).toBe('ít đá');
    expect(r.note).toBe('');
  });
  it('rejects bad input', () => {
    expect(ruleCode(() => parseOrderRequest({ ...ok, items: [] }))).toBe('invalid_request');
    expect(
      ruleCode(() => parseOrderRequest({ ...ok, items: [{ product_id: 'p1', size: 'M', quantity: 0 }] })),
    ).toBe('invalid_request');
    expect(ruleCode(() => parseOrderRequest({ ...ok, payment_method: 'card' }))).toBe('invalid_request');
    expect(ruleCode(() => parseOrderRequest({ ...ok, address_id: '' }))).toBe('invalid_request');
  });
});

describe('checkCanOrder', () => {
  const base = { customer, settings, now: vn10am, shippersOnShift: null };
  it('passes when open and verified', () => {
    expect(ruleCode(() => checkCanOrder(base))).toBe('ok');
  });
  it('blocks per rule', () => {
    expect(ruleCode(() => checkCanOrder({ ...base, customer: { ...customer, role: 'staff' } }))).toBe('not_customer');
    expect(ruleCode(() => checkCanOrder({ ...base, customer: { ...customer, verified: false } }))).toBe('not_verified');
    expect(ruleCode(() => checkCanOrder({ ...base, customer: { ...customer, isActive: false } }))).toBe('locked');
    expect(ruleCode(() => checkCanOrder({ ...base, settings: { ...settings, onlinePaused: true } }))).toBe('paused');
    expect(ruleCode(() => checkCanOrder({ ...base, settings: { ...settings, location: null } }))).toBe('shop_no_location');
    expect(ruleCode(() => checkCanOrder({ ...base, now: new Date('2026-11-23T16:00:00Z') }))).toBe('closed');
    expect(
      ruleCode(() =>
        checkCanOrder({ ...base, settings: { ...settings, requireShipperOnShift: true }, shippersOnShift: 0 }),
      ),
    ).toBe('no_shipper');
  });
});

describe('priceItems / limits / fee', () => {
  const products = new Map([
    ['p1', parseProduct('p1', { name: 'Cà Phê Sữa Đá', category: 'Cà phê', price: { S: 25000, M: 29000 } })],
    ['p2', parseProduct('p2', { name: 'Bánh Flan', price: { default: 20000 }, is_available: false })],
  ]);
  it('uses server prices, never client ones', () => {
    const r = priceItems([{ product_id: 'p1', size: 'M', quantity: 2, note: '' }], products);
    expect(r.subtotal).toBe(58000);
    expect(r.items[0]).toMatchObject({ name: 'Cà Phê Sữa Đá', unit_price: 29000, line_total: 58000 });
  });
  it('rejects sold-out, missing and wrong size', () => {
    expect(ruleCode(() => priceItems([{ product_id: 'p2', size: 'default', quantity: 1, note: '' }], products))).toBe('sold_out');
    expect(ruleCode(() => priceItems([{ product_id: 'x', size: 'M', quantity: 1, note: '' }], products))).toBe('product_missing');
    expect(ruleCode(() => priceItems([{ product_id: 'p1', size: 'L', quantity: 1, note: '' }], products))).toBe('bad_size');
  });
  it('min order and radius', () => {
    expect(ruleCode(() => checkDeliveryLimits(40000, 2, settings))).toBe('below_min');
    expect(ruleCode(() => checkDeliveryLimits(60000, 9.2, settings))).toBe('too_far');
    expect(ruleCode(() => checkDeliveryLimits(60000, 3, settings))).toBe('ok');
  });
  it('shipping fee formula (disabled → 0)', () => {
    expect(shippingFee(settings.shippingFee, 10)).toBe(0);
    const on = { ...settings.shippingFee, enabled: true };
    expect(shippingFee(on, 3)).toBe(15000);
    expect(shippingFee(on, 3.2)).toBe(20000);
  });
});

describe('Firestore value encoding', () => {
  it('round trips', () => {
    const d = new Date('2026-11-23T03:00:00.000Z');
    const back = decodeFields(
      encodeFields({ a: 1, b: 1.5, c: 'x', d: true, e: null, f: [1, 'y'], g: { h: 2 }, t: new Ts(d) }),
    );
    expect(back).toEqual({ a: 1, b: 1.5, c: 'x', d: true, e: null, f: [1, 'y'], g: { h: 2 }, t: d });
  });
});

describe('ID token claims', () => {
  const now = 1_800_000_000;
  const good = {
    aud: 'meowcoffee-cb07b',
    iss: 'https://securetoken.google.com/meowcoffee-cb07b',
    sub: 'u1',
    iat: now - 10,
    auth_time: now - 10,
    exp: now + 3000,
  };
  it('accepts valid and rejects wrong project / expired', () => {
    expect(() => checkClaims(good, 'meowcoffee-cb07b', now)).not.toThrow();
    expect(() => checkClaims({ ...good, aud: 'dacs-9fe78' }, 'meowcoffee-cb07b', now)).toThrow();
    expect(() => checkClaims({ ...good, exp: now - 1000 }, 'meowcoffee-cb07b', now)).toThrow();
  });
  it('base64url round trip', () => {
    expect(new TextDecoder().decode(base64UrlDecode(base64UrlEncode('xin chào ~?')))).toBe('xin chào ~?');
  });
});

describe('distance', () => {
  it('haversine Hoàn Kiếm → Ba Đình ≈ 2 km', () => {
    const km = haversineKm({ lat: 21.0285, lng: 105.8542 }, { lat: 21.0369, lng: 105.8347 });
    expect(km).toBeGreaterThan(1.8);
    expect(km).toBeLessThan(2.4);
  });
});
