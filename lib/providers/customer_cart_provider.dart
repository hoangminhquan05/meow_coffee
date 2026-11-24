import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/firestore_paths.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// Một dòng giỏ của khách: chỉ lưu mã món, size, số lượng, ghi chú.
/// Giá / tên / trạng thái hết hàng luôn lấy theo thực đơn hiện tại.
class CustomerCartLine {
  final String productId;
  final String size;
  final int quantity;
  final String note;

  /// Món tương ứng trong thực đơn hiện tại (null = không còn trong thực đơn).
  final Product? product;

  const CustomerCartLine({
    required this.productId,
    required this.size,
    required this.quantity,
    required this.note,
    this.product,
  });

  String get key => '$productId|$size|${note.trim()}';

  /// Còn đặt được: món còn trong thực đơn, đang bán, còn size này.
  bool get isOrderable =>
      product != null && product!.isAvailable && product!.prices.containsKey(size);

  /// Lý do không đặt được (null nếu đặt được).
  String? get problem {
    if (product == null) return 'Món không còn trong thực đơn';
    if (!product!.isAvailable) return 'Hết hàng';
    if (!product!.prices.containsKey(size)) return 'Không còn size $size';
    return null;
  }

  int get unitPrice => product?.priceOf(size) ?? 0;
  int get lineTotal => unitPrice * quantity;

  String get displayName {
    final name = product?.name ?? 'Món đã ngừng bán';
    return size == Product.defaultSize ? name : '$name ($size)';
  }

  CustomerCartLine copyWith({String? size, int? quantity, String? note, Product? product}) =>
      CustomerCartLine(
        productId: productId,
        size: size ?? this.size,
        quantity: quantity ?? this.quantity,
        note: note ?? this.note,
        product: product ?? this.product,
      );

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'size': size,
        'quantity': quantity,
        'note': note.trim(),
      };

  static CustomerCartLine? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['product_id'], size = raw['size'], qty = raw['quantity'];
    if (id is! String || size is! String || qty is! num || qty < 1) return null;
    return CustomerCartLine(
      productId: id,
      size: size,
      quantity: qty.toInt(),
      note: raw['note']?.toString() ?? '',
    );
  }
}

/// Giỏ hàng của khách, lưu ở Firestore `carts/{uid}` để đồng bộ giữa các
/// thiết bị; đăng xuất vẫn giữ. Ghi gộp sau 1 giây kể từ lần sửa cuối.
class CustomerCartProvider extends ChangeNotifier {
  static const maxLines = 30;
  static const maxQuantity = 50;
  static const _writeDelay = Duration(seconds: 1);

  String? _uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cartSub;
  StreamSubscription<List<Product>>? _productSub;
  Map<String, Product> _products = {};
  List<CustomerCartLine> _lines = [];
  bool _loaded = false;
  bool _dirty = false;
  Timer? _writeTimer;
  Object? _error;

  List<CustomerCartLine> get lines => List.unmodifiable(_lines);
  bool get isLoaded => _loaded;
  bool get isEmpty => _lines.isEmpty;
  Object? get error => _error;
  int get totalItems => _lines.fold(0, (s, l) => s + l.quantity);
  int get subtotal => _lines.fold(0, (s, l) => s + l.lineTotal);

  /// Tất cả dòng đều đặt được.
  bool get allOrderable => _lines.isNotEmpty && _lines.every((l) => l.isOrderable);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection(FsCollections.carts).doc(uid);

  /// Gọi khi đăng nhập/đăng xuất: chỉ chạy với tài khoản khách.
  void bindTo(String? customerUid) =>
      scheduleMicrotask(() => _bind(customerUid));

  void _bind(String? uid) {
    if (uid == _uid) return;
    _flushNow();
    _cartSub?.cancel();
    _productSub?.cancel();
    _cartSub = null;
    _productSub = null;
    _uid = uid;
    _lines = [];
    _loaded = false;
    _error = null;
    if (uid == null) {
      notifyListeners();
      return;
    }
    _productSub = ProductService.watchAll().listen((list) {
      _products = {for (final p in list) p.id: p};
      _lines = [for (final l in _lines) l.copyWith(product: _products[l.productId])];
      notifyListeners();
    });
    _cartSub = _doc(uid).snapshots().listen(
      (snap) {
        // Đang có thay đổi chưa ghi → giữ bản trên máy, tránh bị ghi đè.
        if (_dirty) return;
        final raw = snap.data()?['items'] as List<dynamic>? ?? const [];
        _lines = [
          for (final r in raw)
            if (CustomerCartLine.fromMap(r) case final l?)
              l.copyWith(product: _products[l.productId]),
        ];
        _loaded = true;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('CustomerCartProvider error: $e');
        _error = e;
        _loaded = true;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void _changed() {
    _dirty = true;
    notifyListeners();
    _writeTimer?.cancel();
    _writeTimer = Timer(_writeDelay, _flushNow);
  }

  Future<void> _flushNow() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    final uid = _uid;
    if (!_dirty || uid == null) return;
    final items = _lines.map((l) => l.toMap()).toList();
    _dirty = false;
    try {
      await _doc(uid).set({
        'items': items,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('CustomerCartProvider write error: $e');
      _error = e;
      notifyListeners();
    }
  }

  /// Thêm món; trùng món + size + ghi chú thì cộng dồn.
  void add(Product product, {required String size, int quantity = 1, String note = ''}) {
    final line = CustomerCartLine(
      productId: product.id,
      size: size,
      quantity: quantity,
      note: note.trim(),
      product: product,
    );
    final i = _lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      final q = (_lines[i].quantity + quantity).clamp(1, maxQuantity);
      _lines[i] = _lines[i].copyWith(quantity: q);
    } else {
      if (_lines.length >= maxLines) {
        throw StateError('Giỏ hàng tối đa $maxLines dòng món');
      }
      _lines.add(line);
    }
    _changed();
  }

  void setQuantity(String key, int quantity) {
    final i = _lines.indexWhere((l) => l.key == key);
    if (i < 0) return;
    if (quantity <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i] = _lines[i].copyWith(quantity: quantity.clamp(1, maxQuantity));
    }
    _changed();
  }

  /// Sửa size/ghi chú/số lượng; trùng dòng khác thì gộp.
  void update(String key, {required String size, required String note, required int quantity}) {
    final i = _lines.indexWhere((l) => l.key == key);
    if (i < 0) return;
    final updated = _lines[i].copyWith(size: size, note: note.trim(), quantity: quantity);
    _lines.removeAt(i);
    final dup = _lines.indexWhere((l) => l.key == updated.key);
    if (dup >= 0) {
      _lines[dup] = _lines[dup].copyWith(
        quantity: (_lines[dup].quantity + updated.quantity).clamp(1, maxQuantity),
      );
    } else {
      _lines.insert(i, updated);
    }
    _changed();
  }

  void remove(String key) {
    _lines.removeWhere((l) => l.key == key);
    _changed();
  }

  /// Bỏ các món không đặt được (hết hàng / ngừng bán).
  void removeUnorderable() {
    _lines.removeWhere((l) => !l.isOrderable);
    _changed();
  }

  /// Xóa giỏ (sau khi đặt đơn thành công) – ghi ngay.
  Future<void> clear() async {
    _lines = [];
    _dirty = true;
    notifyListeners();
    await _flushNow();
  }

  @override
  void dispose() {
    _flushNow();
    _cartSub?.cancel();
    _productSub?.cancel();
    super.dispose();
  }
}
