import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Một dòng trong giỏ. Cùng món nhưng khác size hoặc ghi chú là dòng riêng.
class CartItem {
  final Product product;
  final String size;
  final int quantity;
  final String note;

  const CartItem({
    required this.product,
    required this.size,
    this.quantity = 1,
    this.note = '',
  });

  static String keyOf(String productId, String size, String note) =>
      '$productId|$size|${note.trim()}';

  String get key => keyOf(product.id, size, note);

  int get unitPrice => product.priceOf(size);
  int get lineTotal => unitPrice * quantity;

  /// "Cà Phê Sữa Đá (M)" hoặc "Bánh Flan".
  String get displayName =>
      size == Product.defaultSize ? product.name : '${product.name} ($size)';

  CartItem copyWith({String? size, int? quantity, String? note}) => CartItem(
        product: product,
        size: size ?? this.size,
        quantity: quantity ?? this.quantity,
        note: note ?? this.note,
      );

  /// Bản chụp để lưu vào đơn (L6).
  OrderItem toOrderItem() => OrderItem(
        productId: product.id,
        name: product.name,
        category: product.category,
        size: size,
        unitPrice: unitPrice,
        quantity: quantity,
        note: note.trim(),
      );
}

/// Giỏ hàng + thông tin đơn đang soạn (loại đơn, bàn, ghi chú).
class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  Fulfillment _fulfillment = Fulfillment.dineIn;
  int? _tableNumber;
  String _orderNote = '';

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  int get subtotal => _items.fold(0, (sum, i) => sum + i.lineTotal);

  /// Chưa làm giảm giá (Q8) → total = subtotal.
  int get total => subtotal;

  int get totalItems => _items.fold(0, (sum, i) => sum + i.quantity);

  Fulfillment get fulfillment => _fulfillment;
  int? get tableNumber => _tableNumber;
  String get orderNote => _orderNote;

  /// Đơn tại quán bắt buộc chọn bàn (Q13).
  bool get isReadyToPay =>
      _items.isNotEmpty &&
      (_fulfillment != Fulfillment.dineIn || _tableNumber != null);

  void addItem(Product product, {required String size, int quantity = 1, String note = ''}) {
    final key = CartItem.keyOf(product.id, size, note);
    final index = _items.indexWhere((i) => i.key == key);
    if (index >= 0) {
      final existing = _items[index];
      _items[index] = existing.copyWith(quantity: existing.quantity + quantity);
    } else {
      _items.add(CartItem(
        product: product,
        size: size,
        quantity: quantity,
        note: note.trim(),
      ));
    }
    notifyListeners();
  }

  /// Sửa size/ghi chú/số lượng của một dòng. Nếu trùng key với dòng khác thì gộp.
  void updateItem(String key, {String? size, String? note, int? quantity}) {
    final index = _items.indexWhere((i) => i.key == key);
    if (index < 0) return;
    final updated = _items[index].copyWith(
      size: size,
      note: note?.trim(),
      quantity: quantity,
    );
    _items.removeAt(index);
    final dup = _items.indexWhere((i) => i.key == updated.key);
    if (dup >= 0) {
      _items[dup] = _items[dup].copyWith(
        quantity: _items[dup].quantity + updated.quantity,
      );
    } else {
      _items.insert(index, updated);
    }
    notifyListeners();
  }

  void increase(String key) {
    final index = _items.indexWhere((i) => i.key == key);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(quantity: _items[index].quantity + 1);
    notifyListeners();
  }

  /// Giảm 1; nếu về 0 thì xóa dòng.
  void decrease(String key) {
    final index = _items.indexWhere((i) => i.key == key);
    if (index < 0) return;
    final item = _items[index];
    if (item.quantity > 1) {
      _items[index] = item.copyWith(quantity: item.quantity - 1);
    } else {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void remove(String key) {
    _items.removeWhere((i) => i.key == key);
    notifyListeners();
  }

  void setFulfillment(Fulfillment value) {
    _fulfillment = value;
    if (value != Fulfillment.dineIn) _tableNumber = null;
    notifyListeners();
  }

  void setTableNumber(int? value) {
    _tableNumber = value;
    notifyListeners();
  }

  void setOrderNote(String value) {
    _orderNote = value;
  }

  /// Xóa giỏ và reset thông tin đơn.
  void clear() {
    _items.clear();
    _fulfillment = Fulfillment.dineIn;
    _tableNumber = null;
    _orderNote = '';
    notifyListeners();
  }
}
