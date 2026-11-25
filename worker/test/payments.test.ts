import { describe, expect, it } from 'vitest';
import { isPaymentExpired } from '../src/payments/expire';
import { canAttach } from '../src/payments/resolve';
import { checkSepayAuth, decideMatch, extractOrderCode, safeEqual } from '../src/payments/sepay';

describe('SePay auth', () => {
  it('accepts "Apikey <key>" only with the right key', () => {
    expect(checkSepayAuth('Apikey abc123', 'abc123')).toBe(true);
    expect(checkSepayAuth('apikey  abc123 ', 'abc123')).toBe(true);
    expect(checkSepayAuth('Bearer abc123', 'abc123')).toBe(false);
    expect(checkSepayAuth('Apikey wrong', 'abc123')).toBe(false);
    expect(checkSepayAuth(null, 'abc123')).toBe(false);
    expect(checkSepayAuth('Apikey abc123', undefined)).toBe(false); // chưa cấu hình khóa → chặn
    expect(safeEqual('a', 'ab')).toBe(false);
  });
});

describe('extractOrderCode', () => {
  it('finds ON code inside bank transfer text', () => {
    expect(extractOrderCode('ON231126005')).toBe('ON-231126-005');
    expect(extractOrderCode('MBVCB.123.NGUYEN VAN A chuyen tien ON231126005 FT24')).toBe('ON-231126-005');
    expect(extractOrderCode('on 231126 005')).toBe('ON-231126-005');
    expect(extractOrderCode('ON-231126-005')).toBe('ON-231126-005');
    expect(extractOrderCode(null, 'abc', 'ON2311260051')).toBeNull(); // dư số → không nhận
    expect(extractOrderCode('chuyen tien an trua')).toBeNull();
  });
});

describe('decideMatch', () => {
  const order = {
    channel: 'online',
    payment_method: 'vietqr',
    status: 'awaiting_payment',
    payment_status: 'unpaid',
    total: 85000,
  };
  it('matches exact amount on awaiting order', () => {
    expect(decideMatch(order, 85000)).toEqual({ ok: true });
  });
  it('flags every mismatch for admin review', () => {
    expect(decideMatch(null, 85000)).toEqual({ ok: false, reason: 'order_not_found' });
    expect(decideMatch(order, 80000)).toEqual({ ok: false, reason: 'amount_mismatch' });
    expect(decideMatch({ ...order, status: 'cancelled' }, 85000)).toEqual({ ok: false, reason: 'not_awaiting' });
    expect(decideMatch({ ...order, payment_method: 'cash' }, 85000)).toEqual({ ok: false, reason: 'not_vietqr' });
  });
});

describe('isPaymentExpired', () => {
  const now = new Date('2026-11-24T03:00:00Z');
  const base = { status: 'awaiting_payment', payment_status: 'unpaid' };
  it('expires only unpaid awaiting orders past the deadline', () => {
    expect(isPaymentExpired({ ...base, payment: { expires_at: new Date('2026-11-24T02:59:00Z') } }, now)).toBe(true);
    expect(isPaymentExpired({ ...base, payment: { expires_at: new Date('2026-11-24T03:01:00Z') } }, now)).toBe(false);
    expect(isPaymentExpired({ ...base, status: 'pending', payment: { expires_at: new Date(0) } }, now)).toBe(false);
    expect(isPaymentExpired({ ...base, payment: {} }, now)).toBe(false);
  });
});

describe('canAttach', () => {
  const order = { channel: 'online', payment_method: 'vietqr', status: 'awaiting_payment', payment_status: 'unpaid' };
  it('allows awaiting or expired-cancelled VietQR orders', () => {
    expect(canAttach(order)).toBeNull();
    expect(canAttach({ ...order, status: 'cancelled', cancel_reason: 'Quá hạn thanh toán' })).toBeNull();
  });
  it('rejects others', () => {
    expect(canAttach({ ...order, status: 'cancelled', cancel_reason: 'Đổi ý' })).not.toBeNull();
    expect(canAttach({ ...order, payment_status: 'paid' })).not.toBeNull();
    expect(canAttach({ ...order, payment_method: 'cash' })).not.toBeNull();
    expect(canAttach(null)).not.toBeNull();
  });
});
