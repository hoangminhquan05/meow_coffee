import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_coffee/services/distance_service.dart';
import 'package:meow_coffee/services/vn_admin_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:meow_coffee/models/shop_settings.dart';
import 'package:meow_coffee/providers/session_provider.dart';
import 'package:meow_coffee/utils/phone.dart';
import 'package:meow_coffee/core/enums.dart';
import 'package:meow_coffee/models/order.dart';
import 'package:meow_coffee/models/product.dart';
import 'package:meow_coffee/models/user_model.dart';
import 'package:meow_coffee/providers/cart_provider.dart';
import 'package:meow_coffee/services/order_service.dart';
import 'package:meow_coffee/utils/formatters.dart';

const coffee = Product(
  id: 'p1',
  name: 'Cà Phê Sữa Đá',
  category: 'Cà phê',
  prices: {'S': 25000, 'M': 29000, 'L': 35000},
);
const flan = Product(id: 'p2', name: 'Bánh Flan', prices: {'default': 20000});

Order _order({
  required String sellerId,
  required DateTime createdAt,
  OrderStatus status = OrderStatus.completed,
}) =>
    Order(
      id: 'o1',
      orderCode: '221126-001',
      channel: OrderChannel.inStore,
      fulfillment: Fulfillment.takeaway,
      tableNumber: null,
      status: status,
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      paymentRef: null,
      seller: PersonRef(id: sellerId, name: 'NV'),
      items: const [],
      subtotal: 0,
      discount: 0,
      total: 0,
      note: '',
      createdAt: createdAt,
    );

void main() {
  test('VnAdminService: bundled 2025 data has 34 provinces and searches without accents', () {
    final raw = File('assets/data/vn_admin_2025.json').readAsStringSync();
    final provinces = VnAdminService.parse(raw);
    expect(provinces.length, 34);
    expect(provinces.fold<int>(0, (s, p) => s + p.wards.length), greaterThan(3000));
    final hn = VnAdminService.search(provinces, 'ha noi');
    expect(hn.map((p) => p.name), contains('Thành phố Hà Nội'));
    final wards = VnAdminService.search(hn.first.wards, 'ba dinh');
    expect(wards.map((w) => w.name), contains('Phường Ba Đình'));
  });

  test('DistanceService.estimateKm = straight line × 1.3', () {
    // Hồ Gươm → Lăng Bác ~2.0 km đường chim bay.
    final km = DistanceService.estimateKm(
      const LatLng(21.0285, 105.8542),
      const LatLng(21.0369, 105.8347),
    );
    expect(km, inInclusiveRange(2.5, 3.0));
  });

  test('Phone: normalize VN mobile numbers to E.164', () {
    expect(toE164Vn('0901 234 567'), '+84901234567');
    expect(toE164Vn('84901234567'), '+84901234567');
    expect(toE164Vn('+84 901-234-567'), '+84901234567');
    expect(toE164Vn('0201234567'), isNull); // đầu số không phải di động
    expect(toE164Vn('090123456'), isNull); // thiếu số
    expect(formatVnPhone('+84901234567'), '0901 234 567');
  });

  test('SessionProvider.homeRouteFor routes by role', () {
    expect(SessionProvider.homeRouteFor(UserRole.customer), '/customer');
    expect(SessionProvider.homeRouteFor(UserRole.shipper), '/shipper');
    expect(SessionProvider.homeRouteFor(UserRole.staff), '/home');
    expect(SessionProvider.homeRouteFor(UserRole.admin), '/home');
    expect(SessionProvider.homeRouteFor(null), '/home');
  });

  test('ShopSettings: opening hours incl. overnight, closed reasons', () {
    const day = ShopSettings(
      location: LatLng(21.02, 105.85),
      openTime: '07:00',
      closeTime: '22:00',
    );
    expect(day.isWithinHours(DateTime(2026, 11, 23, 6, 59)), isFalse);
    expect(day.isWithinHours(DateTime(2026, 11, 23, 7, 0)), isTrue);
    expect(day.isWithinHours(DateTime(2026, 11, 23, 22, 0)), isFalse);

    const night = ShopSettings(openTime: '18:00', closeTime: '02:00');
    expect(night.isWithinHours(DateTime(2026, 11, 23, 23, 30)), isTrue);
    expect(night.isWithinHours(DateTime(2026, 11, 24, 1, 59)), isTrue);
    expect(night.isWithinHours(DateTime(2026, 11, 24, 12, 0)), isFalse);

    final noon = DateTime(2026, 11, 23, 12);
    expect(day.closedReason(noon), isNull);
    expect(const ShopSettings().closedReason(noon), contains('vị trí'));
    expect(
      const ShopSettings(location: LatLng(0, 0), onlinePaused: true)
          .closedReason(noon),
      contains('tạm ngưng'),
    );
  });

  test('ShippingFeeConfig: disabled = 0, base + per started km', () {
    const off = ShippingFeeConfig();
    expect(off.feeFor(10), 0);
    const on = ShippingFeeConfig(enabled: true);
    expect(on.feeFor(2.5), 15000);
    expect(on.feeFor(3), 15000);
    expect(on.feeFor(3.2), 20000);
    expect(on.feeFor(5), 25000);
  });

  test('ShopSettings: toMap/fromMap round trip', () {
    const s = ShopSettings(
      name: 'Meow',
      location: LatLng(21.1, 105.9),
      onlinePaused: true,
      minOrderValue: 0,
      shippingFee: ShippingFeeConfig(enabled: true, perKm: 6000),
      dispatch: DispatchConfig(maxOrdersPerShipper: 2),
    );
    final back = ShopSettings.fromMap(s.toMap());
    expect(back.name, 'Meow');
    expect(back.location, const LatLng(21.1, 105.9));
    expect(back.onlinePaused, isTrue);
    expect(back.minOrderValue, 0);
    expect(back.shippingFee.perKm, 6000);
    expect(back.dispatch.maxOrdersPerShipper, 2);
    expect(back.dispatch.weights.load, 3);
  });

  test('Product: size order, price label, no-size products', () {
    expect(coffee.hasSizes, isTrue);
    expect(coffee.sizes, ['S', 'M', 'L']);
    expect(coffee.priceLabel, '25.000đ – 35.000đ');
    expect(flan.hasSizes, isFalse);
    expect(flan.sizes, [Product.defaultSize]);
    expect(flan.priceLabel, '20.000đ');
  });

  test('normalizeVietnamese / formatters', () {
    expect(normalizeVietnamese('Trà Sữa Đường Đen'), 'tra sua duong den');
    expect(formatVnd(125000, suffix: 'đ'), '125.000 đ');
    expect(formatMoney(98000), '98.000đ');
  });

  test('CartProvider: same product with different size/note is a separate line', () {
    final cart = CartProvider();
    cart.addItem(coffee, size: 'M', quantity: 2);
    cart.addItem(coffee, size: 'M', quantity: 1);
    cart.addItem(coffee, size: 'M', note: 'ít đá');
    cart.addItem(coffee, size: 'L');
    expect(cart.items.length, 3);
    expect(cart.totalItems, 5);
    expect(cart.subtotal, 29000 * 4 + 35000);
    expect(cart.total, cart.subtotal);

    final key = CartItem.keyOf('p1', 'M', '');
    cart.updateItem(key, size: 'L'); // gộp với dòng size L
    expect(cart.items.length, 2);
    expect(cart.items.firstWhere((i) => i.size == 'L' && i.note.isEmpty).quantity, 4);

    cart.decrease(CartItem.keyOf('p1', 'M', 'ít đá'));
    expect(cart.items.length, 1);
  });

  test('CartProvider: dine-in requires a table, takeaway clears it', () {
    final cart = CartProvider()..addItem(flan, size: Product.defaultSize);
    expect(cart.fulfillment, Fulfillment.dineIn);
    expect(cart.isReadyToPay, isFalse);
    cart.setTableNumber(5);
    expect(cart.isReadyToPay, isTrue);
    cart.setFulfillment(Fulfillment.takeaway);
    expect(cart.tableNumber, isNull);
    expect(cart.isReadyToPay, isTrue);
    cart.clear();
    expect(cart.isEmpty, isTrue);
    expect(cart.fulfillment, Fulfillment.dineIn);
  });

  test('OrderService.canCancel: staff own order within 30 minutes, admin always', () {
    final now = DateTime(2026, 11, 22, 10, 0);
    const staff = UserModel(uid: 's1', role: UserRole.staff);
    const other = UserModel(uid: 's2', role: UserRole.staff);
    const admin = UserModel(uid: 'a1', role: UserRole.admin);

    final at29 = _order(sellerId: 's1', createdAt: now.subtract(const Duration(minutes: 29)));
    final at31 = _order(sellerId: 's1', createdAt: now.subtract(const Duration(minutes: 31)));
    final old = _order(sellerId: 's1', createdAt: now.subtract(const Duration(days: 3)));
    final cancelled = _order(
      sellerId: 's1',
      createdAt: now,
      status: OrderStatus.cancelled,
    );

    expect(OrderService.canCancel(at29, staff, now: now), isTrue);
    expect(OrderService.canCancel(at31, staff, now: now), isFalse);
    expect(OrderService.canCancel(at29, other, now: now), isFalse);
    expect(OrderService.canCancel(old, admin, now: now), isTrue);
    expect(OrderService.canCancel(cancelled, admin, now: now), isFalse);
  });
}
