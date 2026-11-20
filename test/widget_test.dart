import 'package:meow_coffee/models/product.dart';
import 'package:meow_coffee/providers/cart_provider.dart';
import 'package:meow_coffee/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Product formats VND price with dot separators', () {
    const product = Product(
      id: '1',
      name: 'Cà phê sữa',
      price: 35000,
    );
    expect(product.formattedPrice, '35.000 VND');
    expect(product.formatPrice(3), '105.000 VND');
  });

  test('normalizeVietnamese strips diacritics for search', () {
    expect(normalizeVietnamese('Trà Sữa Đường Đen'), 'tra sua duong den');
    expect(formatVnd(125000, suffix: 'đ'), '125.000 đ');
  });

  test('CartProvider adds, updates, and clears items', () {
    final cart = CartProvider();
    const product = Product(id: '1', name: 'Trà sữa', price: 40000);

    cart.addToCart(product, quantity: 2);
    expect(cart.totalItems, 2);
    expect(cart.totalPrice, 80000);

    cart.increaseQuantity(product);
    expect(cart.totalItems, 3);
    expect(cart.totalPrice, 120000);

    cart.decreaseQuantity(product);
    expect(cart.totalItems, 2);

    cart.clearCart();
    expect(cart.cartItems, isEmpty);
    expect(cart.totalPrice, 0.0);
  });
}
