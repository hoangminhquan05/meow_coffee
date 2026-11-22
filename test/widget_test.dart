import 'package:flutter_test/flutter_test.dart';
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
