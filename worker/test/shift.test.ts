import { describe, expect, it } from 'vitest';
import { OrderRuleError } from '../src/orders/rules';
import { isShiftStale, parseShiftRequest, SHIFT_STALE_MIN } from '../src/shipper/shift';

const now = new Date('2026-11-26T03:00:00Z');
const minutesAgo = (m: number) => new Date(now.getTime() - m * 60_000);

describe('parseShiftRequest', () => {
  it('start needs a valid location', () => {
    expect(parseShiftRequest({ action: 'start', location: { lat: 16.05, lng: 108.2 } })).toEqual({
      action: 'start',
      location: { lat: 16.05, lng: 108.2 },
    });
    expect(() => parseShiftRequest({ action: 'start' })).toThrow(OrderRuleError);
    expect(() => parseShiftRequest({ action: 'start', location: { lat: 91, lng: 0 } })).toThrow(
      OrderRuleError,
    );
  });

  it('end needs nothing else, unknown action rejected', () => {
    expect(parseShiftRequest({ action: 'end' })).toEqual({ action: 'end' });
    expect(() => parseShiftRequest({ action: 'pause' })).toThrow(OrderRuleError);
    expect(() => parseShiftRequest(null)).toThrow(OrderRuleError);
  });
});

describe('isShiftStale', () => {
  it('ends shift after the GPS has been silent too long', () => {
    expect(isShiftStale({ on_shift: true, location_updated_at: minutesAgo(SHIFT_STALE_MIN + 1) }, now)).toBe(
      true,
    );
    expect(isShiftStale({ on_shift: true, location_updated_at: minutesAgo(SHIFT_STALE_MIN - 1) }, now)).toBe(
      false,
    );
  });

  it('never ends a shift that still holds orders or is already off', () => {
    expect(
      isShiftStale(
        { on_shift: true, location_updated_at: minutesAgo(60), active_order_ids: ['o1'] },
        now,
      ),
    ).toBe(false);
    expect(isShiftStale({ on_shift: false, location_updated_at: minutesAgo(60) }, now)).toBe(false);
  });

  it('falls back to shift start when no GPS was ever sent', () => {
    expect(isShiftStale({ on_shift: true, shift_started_at: minutesAgo(5) }, now)).toBe(false);
    expect(isShiftStale({ on_shift: true }, now)).toBe(true);
  });
});
