import { describe, expect, it } from 'vitest';
import { hasLiveOffer, needsDispatch } from '../src/dispatch/dispatch';
import {
  amountToCollect,
  bestRouteKm,
  declineWarning,
  failureBlocker,
  parseDispatchConfig,
  pickBest,
  scoreCandidate,
  vnDayKey,
  type Candidate,
} from '../src/dispatch/score';
import { checkStaffAction, parseStaffRequest } from '../src/dispatch/staff';
import { checkShipperAction, parseShipperRequest } from '../src/shipper/delivery';
import { OrderRuleError } from '../src/orders/rules';

const now = new Date('2026-11-27T03:00:00Z');
const ago = (m: number) => new Date(now.getTime() - m * 60_000);
const cfg = parseDispatchConfig(null);
const shop = { lat: 16.06, lng: 108.22 };
// ~1.1 km mỗi 0.01 độ vĩ
const north = (km: number) => ({ lat: shop.lat + km / 111, lng: shop.lng });

const cand = (over: Partial<Candidate>): Candidate => ({
  uid: 'a',
  name: 'A',
  phone: '',
  location: shop,
  locationAt: ago(1),
  heldDrops: [],
  heldAllAtShop: true,
  deliveredToday: 0,
  ...over,
});

describe('scoring', () => {
  it('prefers the shipper closer to the shop', () => {
    const near = cand({ uid: 'near', location: north(0.5) });
    const far = cand({ uid: 'far', location: north(4) });
    expect(pickBest([far, near], shop, north(2), cfg, now)?.candidate.uid).toBe('near');
  });

  it('stale GPS counts as being at the shop', () => {
    const s = scoreCandidate(cand({ location: north(5), locationAt: ago(30) }), shop, north(2), cfg, now)!;
    expect(s.pickupKm).toBe(0);
  });

  it('batches only nearby drops while all held orders are still at the shop', () => {
    const drop = north(2);
    const holding = cand({ heldDrops: [north(2.5)] });
    expect(scoreCandidate(holding, shop, drop, cfg, now)).not.toBeNull();
    expect(scoreCandidate({ ...holding, heldAllAtShop: false }, shop, drop, cfg, now)).toBeNull();
    expect(scoreCandidate({ ...holding, heldDrops: [north(5)] }, shop, drop, cfg, now)).toBeNull();
    const full = cand({ heldDrops: [north(2), north(2.1), north(2.2)] });
    expect(scoreCandidate(full, shop, drop, cfg, now)).toBeNull();
  });

  it('same-direction batching beats a full new trip; load and delivered-today add up', () => {
    const idle = scoreCandidate(cand({}), shop, north(2), cfg, now)!;
    const one = scoreCandidate(cand({ heldDrops: [north(2.2)] }), shop, north(2), cfg, now)!;
    const two = scoreCandidate(cand({ heldDrops: [north(2.2), north(2.4)] }), shop, north(2), cfg, now)!;
    const tired = scoreCandidate(cand({ deliveredToday: 10 }), shop, north(2), cfg, now)!;
    expect(one.detourKm).toBeCloseTo(0, 5);
    expect(one.score).toBeLessThan(idle.score);
    expect(two.score).toBeGreaterThan(one.score);
    expect(tired.score).toBeGreaterThan(idle.score);
  });

  it('best route tries every order of stops', () => {
    const a = north(1);
    const b = north(3);
    expect(bestRouteKm(shop, [b, a])).toBeCloseTo(bestRouteKm(shop, [b]), 5);
  });
});

describe('offers', () => {
  it('needsDispatch: offer when idle, timeout when expired, nothing while running/assigned', () => {
    const base = { channel: 'online', status: 'ready', delivery: { shipper: null } };
    expect(needsDispatch(base, now)).toBe('offer');
    expect(needsDispatch({ ...base, dispatch: { state: 'no_shipper' } }, now)).toBe('offer');
    expect(needsDispatch({ ...base, dispatch: { state: 'offering', expires_at: ago(-0.5) } }, now)).toBeNull();
    expect(needsDispatch({ ...base, dispatch: { state: 'offering', expires_at: ago(0.1) } }, now)).toBe('timeout');
    expect(needsDispatch({ ...base, delivery: { shipper: { id: 's' } } }, now)).toBeNull();
    expect(needsDispatch({ ...base, status: 'preparing' }, now)).toBeNull();
  });

  it('hasLiveOffer ignores expired offers and the same order', () => {
    const s = { pending_offer: { order_id: 'o1', expires_at: ago(-0.5) } };
    expect(hasLiveOffer(s, now)).toBe(true);
    expect(hasLiveOffer(s, now, 'o1')).toBe(false);
    expect(hasLiveOffer({ pending_offer: { order_id: 'o1', expires_at: ago(1) } }, now)).toBe(false);
    expect(hasLiveOffer({ pending_offer: null }, now)).toBe(false);
  });

  it('decline warnings: 2nd warns, 3rd+ also notifies admin', () => {
    expect(declineWarning(1).message).toBeNull();
    expect(declineWarning(2)).toMatchObject({ notifyAdmin: false });
    expect(declineWarning(2).message).toContain('2');
    expect(declineWarning(4)).toMatchObject({ notifyAdmin: true });
  });
});

describe('delivery rules', () => {
  it('amount to collect: COD whole order, VietQR only redelivery fees', () => {
    expect(amountToCollect({ payment_method: 'cash', payment_status: 'unpaid', total: 80000 })).toBe(80000);
    expect(amountToCollect({ payment_method: 'vietqr', payment_status: 'paid', total: 95000 })).toBe(0);
    expect(
      amountToCollect({ payment_method: 'vietqr', extra_fees: [{ reason: 'redelivery', amount: 15000 }] }),
    ).toBe(15000);
  });

  it('failure needs arrival + wait + calls (O29)', () => {
    const f = { waitMinutes: 10, minCallAttempts: 2 };
    expect(failureBlocker({}, f, now)).toContain('Đã đến nơi');
    expect(failureBlocker({ arrived_at: ago(5), call_attempts: [1, 2] }, f, now)).toContain('10 phút');
    expect(failureBlocker({ arrived_at: ago(11), call_attempts: [1] }, f, now)).toContain('2 lần');
    expect(failureBlocker({ arrived_at: ago(11), call_attempts: [1, 2] }, f, now)).toBeNull();
  });

  it('shipper actions only on own order in the right status', () => {
    const o = { channel: 'online', status: 'ready', delivery: { shipper: { id: 's1' } } };
    expect(() => checkShipperAction(o, 's1', 'picked_up')).not.toThrow();
    expect(() => checkShipperAction(o, 's2', 'picked_up')).toThrow(OrderRuleError);
    expect(() => checkShipperAction(o, 's1', 'delivered')).toThrow(OrderRuleError);
    expect(() => parseShipperRequest({ action: 'failed' })).toThrow(OrderRuleError);
    expect(parseShipperRequest({ action: 'delivered', collected: true })).toEqual({
      action: 'delivered',
      collected: true,
    });
  });

  it('staff actions check status', () => {
    expect(() => parseStaffRequest({ action: 'assign' })).toThrow(OrderRuleError);
    expect(() => parseStaffRequest({ action: 'cancel', reason: ' ' })).toThrow(OrderRuleError);
    const ready = { channel: 'online', status: 'ready', delivery: { shipper: null } };
    expect(() => checkStaffAction(ready, { action: 'retry' })).not.toThrow();
    expect(() =>
      checkStaffAction({ ...ready, delivery: { shipper: { id: 's' } } }, { action: 'retry' }),
    ).toThrow(OrderRuleError);
    expect(() => checkStaffAction(ready, { action: 'redeliver' })).toThrow(OrderRuleError);
    expect(() => checkStaffAction({ ...ready, status: 'delivery_failed' }, { action: 'cancel', reason: 'x' })).not.toThrow();
  });

  it('day key uses Vietnam time', () => {
    expect(vnDayKey(new Date('2026-11-27T18:00:00Z'))).toBe('20261128');
  });
});
