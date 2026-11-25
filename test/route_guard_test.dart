import 'package:flutter_test/flutter_test.dart';
import 'package:meow_coffee/core/enums.dart';
import 'package:meow_coffee/core/route_guard.dart';

void main() {
  test('each role has its own home', () {
    expect(homeRouteFor(UserRole.customer), '/customer');
    expect(homeRouteFor(UserRole.shipper), '/shipper');
    expect(homeRouteFor(UserRole.staff), '/home');
    expect(homeRouteFor(UserRole.admin), '/home');
  });

  test('shipper and customer are sent back from staff screens', () {
    for (final r in ['/home', '/profile', '/cart', '/online_orders', '/shop_settings']) {
      expect(guardRoute(r, UserRole.shipper), '/shipper', reason: r);
      expect(guardRoute(r, UserRole.customer), '/customer', reason: r);
    }
  });

  test('staff cannot open admin, customer or shipper screens', () {
    expect(guardRoute('/home', UserRole.staff), isNull);
    expect(guardRoute('/online_order', UserRole.staff), isNull);
    expect(guardRoute('/shop_settings', UserRole.staff), '/home');
    expect(guardRoute('/checkout', UserRole.staff), '/home');
    expect(guardRoute('/shipper', UserRole.staff), '/home');
    expect(guardRoute('/shop_settings', UserRole.admin), isNull);
  });

  test('shared screens open for everyone; signed-out is not redirected', () {
    for (final role in UserRole.values) {
      expect(guardRoute('/change_password', role), isNull);
      expect(guardRoute('/product_detail', role), isNull);
      expect(guardRoute('/login', role), isNull);
    }
    expect(guardRoute('/home', null), isNull);
    expect(guardRoute('/shipper', UserRole.customer), '/customer');
  });
}
