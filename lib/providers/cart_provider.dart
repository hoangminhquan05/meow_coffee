import 'package:flutter/foundation.dart';

import '../models/product.dart';

class CartItem {
  final Product product;
  final int quantity;

  const CartItem({
    required this.product,
    this.quantity = 1,
  });

  double get totalPrice => product.price * quantity;

  CartItem copyWith({
    Product? product,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _cartItems = [];

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  double get totalPrice =>
      _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  int get totalItems =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);

  void addToCart(Product product, {int quantity = 1}) {
    final index = _cartItems.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final existing = _cartItems[index];
      _cartItems[index] = existing.copyWith(quantity: existing.quantity + quantity);
    } else {
      _cartItems.add(CartItem(product: product, quantity: quantity));
    }
    notifyListeners();
  }

  void removeFromCart(Product product) {
    _cartItems.removeWhere((item) => item.product.id == product.id);
    notifyListeners();
  }

  void increaseQuantity(Product product) {
    final index = _cartItems.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final existing = _cartItems[index];
      _cartItems[index] = existing.copyWith(quantity: existing.quantity + 1);
      notifyListeners();
    }
  }

  void decreaseQuantity(Product product) {
    final index = _cartItems.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final existing = _cartItems[index];
      if (existing.quantity > 1) {
        _cartItems[index] = existing.copyWith(quantity: existing.quantity - 1);
      } else {
        _cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  void processPayment(String paymentMethod) {
    clearCart();
  }
}
