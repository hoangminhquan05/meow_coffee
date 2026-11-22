import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/formatters.dart';

/// Sản phẩm trong `products/{id}`.
/// Giá theo size: `price: {S, M, L}`; món không chia size: `price: {default}`.
class Product {
  static const defaultSize = 'default';
  static const sizeOrder = ['S', 'M', 'L'];

  final String id;
  final String name;
  final String category;
  final String description;
  final String imageUrl;
  final Map<String, int> prices;
  final bool isAvailable;
  final DateTime? createdAt;

  const Product({
    this.id = '',
    this.name = '',
    this.category = '',
    this.description = '',
    this.imageUrl = '',
    this.prices = const {},
    this.isAvailable = true,
    this.createdAt,
  });

  /// Món có chia size (S/M/L) hay không.
  bool get hasSizes =>
      prices.isNotEmpty && !prices.containsKey(defaultSize);

  /// Các size món có, theo thứ tự S → M → L (size lạ xếp cuối).
  List<String> get sizes {
    if (!hasSizes) return const [defaultSize];
    final known = sizeOrder.where(prices.containsKey).toList();
    final others = prices.keys.where((k) => !sizeOrder.contains(k)).toList()
      ..sort();
    return [...known, ...others];
  }

  int priceOf(String size) => prices[size] ?? 0;

  int get minPrice =>
      prices.isEmpty ? 0 : prices.values.reduce((a, b) => a < b ? a : b);

  int get maxPrice =>
      prices.isEmpty ? 0 : prices.values.reduce((a, b) => a > b ? a : b);

  /// "25.000đ" hoặc "25.000đ – 35.000đ".
  String get priceLabel => minPrice == maxPrice
      ? formatMoney(minPrice)
      : '${formatMoney(minPrice)} – ${formatMoney(maxPrice)}';

  static String sizeLabel(String size) =>
      size == defaultSize ? '' : 'Size $size';

  static Map<String, int> _parsePrices(dynamic raw) {
    if (raw is Map) {
      final result = <String, int>{};
      raw.forEach((k, v) {
        if (v is num) result[k.toString()] = v.round();
      });
      return result;
    }
    if (raw is num) return {defaultSize: raw.round()};
    return const {};
  }

  factory Product.fromMap(Map<String, dynamic> map, {required String id}) {
    final created = map['created_at'];
    return Product(
      id: id,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      description: map['description'] as String? ?? '',
      imageUrl: map['image_url'] as String? ?? '',
      prices: _parsePrices(map['price']),
      isAvailable: map['is_available'] as bool? ?? true,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Product.fromMap(doc.data() ?? const {}, id: doc.id);

  /// Dữ liệu ghi Firestore (không gồm `id`, `created_at`).
  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'description': description,
        'image_url': imageUrl,
        'price': prices,
        'is_available': isAvailable,
      };

  Product copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    String? imageUrl,
    Map<String, int>? prices,
    bool? isAvailable,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      prices: prices ?? this.prices,
      isAvailable: isAvailable ?? this.isAvailable,
      createdAt: createdAt,
    );
  }
}
