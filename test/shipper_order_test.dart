import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meow_coffee/core/enums.dart';
import 'package:meow_coffee/core/route_guard.dart';
import 'package:meow_coffee/models/order.dart';
import 'package:meow_coffee/screens/shipper/shift_offer_stats.dart';
import 'package:meow_coffee/services/shipper_order_service.dart';

Order _order(String id, {String method = 'cash', String paid = 'unpaid', List<Map>? fees, LatLng? at}) =>
    Order.fromMap({
      'channel': 'online',
      'status': 'delivering',
      'payment_method': method,
      'payment_status': paid,
      'total': 80000,
      'extra_fees': fees ?? [],
      'delivery': {
        if (at != null) 'location': {'lat': at.latitude, 'lng': at.longitude},
      },
    }, id: id);

void main() {
  test('amountToCollect: COD whole order, VietQR only redelivery fee', () {
    expect(_order('a').amountToCollect, 80000);
    expect(_order('b', method: 'vietqr', paid: 'paid').amountToCollect, 0);
    expect(
      _order('c', method: 'vietqr', paid: 'paid', fees: [
        {'reason': 'redelivery', 'amount': 15000}
      ]).amountToCollect,
      15000,
    );
  });

  test('suggestRoute visits the nearest drop first', () {
    const shop = LatLng(16.06, 108.22);
    final far = _order('far', at: const LatLng(16.09, 108.22));
    final near = _order('near', at: const LatLng(16.07, 108.22));
    final ids = ShipperOrderService.suggestRoute(shop, [far, near]).map((o) => o.id);
    expect(ids, ['near', 'far']);
  });

  test('failure wait countdown', () {
    final now = DateTime(2026, 11, 27, 10);
    expect(ShipperOrderService.minutesLeft(null, 10, now), 10);
    expect(ShipperOrderService.minutesLeft(now.subtract(const Duration(minutes: 4)), 10, now), 6);
    expect(ShipperOrderService.minutesLeft(now.subtract(const Duration(minutes: 12)), 10, now), 0);
  });

  test('shift offer stats ignore offers the shop withdrew', () {
    final s = OfferStats.fromResults(
        ['accepted', 'declined', 'timeout', 'timeout', 'cancelled', null]);
    expect(s.offered, 5); // null = đang mời, vẫn tính là 1 lời mời
    expect(s.accepted, 1);
    expect(s.declined, 1);
    expect(s.timeout, 2);
    expect(s.missed, 3);
    expect(missedNote(1), isNull);
    expect(missedNote(3), contains('Quản lý'));
  });

  test('shipper order screen is shipper-only', () {
    expect(guardRoute('/shipper_order', UserRole.shipper), isNull);
    expect(guardRoute('/shipper_order', UserRole.staff), '/home');
  });
}
