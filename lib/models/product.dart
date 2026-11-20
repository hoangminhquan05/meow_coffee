import 'package:intl/intl.dart';

class Product {
  final String id;
  final String imageUrl;
  final String name;
  final double price;
  final String description;
  final String category;

  const Product({
    this.id = '',
    this.imageUrl = '',
    this.name = '',
    this.price = 0.0,
    this.description = '',
    this.category = '',
  });

  String get formattedPrice => formatPrice(1);

  String formatPrice([int quantity = 1]) {
    final total = price * quantity;
    final formatted =
        NumberFormat('#,##0', 'en_US').format(total).replaceAll(',', '.');
    return '$formatted VND';
  }

  factory Product.fromMap(Map<String, dynamic> map, {String? docId}) {
    final rawPrice = map['price'];
    final double parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;

    return Product(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : (docId ?? ''),
      imageUrl: map['imageUrl'] as String? ?? '',
      name: map['name'] as String? ?? '',
      price: parsedPrice,
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'name': name,
      'price': price,
      'description': description,
      'category': category,
    };
  }

  Product copyWith({
    String? id,
    String? imageUrl,
    String? name,
    double? price,
    String? description,
    String? category,
  }) {
    return Product(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      name: name ?? this.name,
      price: price ?? this.price,
      description: description ?? this.description,
      category: category ?? this.category,
    );
  }
}
