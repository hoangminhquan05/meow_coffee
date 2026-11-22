import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../core/enums.dart';
import 'product.dart';

/// Tham chiếu người (seller, cancelled_by…) – lưu kèm tên để lịch sử không đổi.
class PersonRef {
  final String id;
  final String name;

  const PersonRef({required this.id, required this.name});

  factory PersonRef.fromMap(dynamic raw) {
    final map = raw is Map ? raw : const {};
    return PersonRef(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

/// Một dòng món trong đơn – bản chụp tại thời điểm bán.
class OrderItem {
  final String productId;
  final String name;
  final String category;
  final String size;
  final int unitPrice;
  final int quantity;
  final String note;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.size,
    required this.unitPrice,
    required this.quantity,
    this.note = '',
  });

  int get lineTotal => unitPrice * quantity;

  /// "Cà Phê Sữa Đá (M)" hoặc "Bánh Flan".
  String get displayName =>
      size == Product.defaultSize ? name : '$name ($size)';

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) => v is num ? v.round() : 0;
    return OrderItem(
      productId: map['product_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      size: map['size']?.toString() ?? Product.defaultSize,
      unitPrice: toInt(map['unit_price']),
      quantity: toInt(map['quantity']),
      note: map['note']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'name': name,
        'category': category,
        'size': size,
        'unit_price': unitPrice,
        'quantity': quantity,
        'note': note,
        'line_total': lineTotal,
      };
}

/// Đơn hàng trong `orders/{id}`.
class Order {
  /// Nhân viên chỉ được hủy đơn của mình trong khoảng thời gian này.
  static const staffCancelWindow = Duration(minutes: 30);

  final String id;
  final String orderCode;
  final OrderChannel channel;
  final Fulfillment fulfillment;
  final int? tableNumber;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final String? paymentRef;
  final PersonRef? seller;
  final List<OrderItem> items;
  final int subtotal;
  final int discount;
  final int total;
  final String note;
  final DateTime? createdAt;
  final DateTime? cancelledAt;
  final PersonRef? cancelledBy;
  final String? cancelReason;

  const Order({
    required this.id,
    required this.orderCode,
    required this.channel,
    required this.fulfillment,
    required this.tableNumber,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.paymentRef,
    required this.seller,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.note,
    required this.createdAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  bool get isCancelled => status == OrderStatus.cancelled;

  int get totalItems => items.fold(0, (s, i) => s + i.quantity);

  /// "Tại quán · Bàn 5" / "Mang đi".
  String get fulfillmentLabel => tableNumber != null
      ? '${fulfillment.label} · Bàn $tableNumber'
      : fulfillment.label;

  factory Order.fromMap(Map<String, dynamic> map, {required String id}) {
    int toInt(dynamic v) => v is num ? v.round() : 0;
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    final rawItems = map['items'] as List<dynamic>? ?? const [];
    final table = map['table_number'];
    return Order(
      id: id,
      orderCode: map['order_code']?.toString() ?? '',
      channel: OrderChannel.fromValue(map['channel'] as String?),
      fulfillment: Fulfillment.fromValue(map['fulfillment'] as String?),
      tableNumber: table is num ? table.toInt() : null,
      status: OrderStatus.fromValue(map['status'] as String?),
      paymentStatus: PaymentStatus.fromValue(map['payment_status'] as String?),
      paymentMethod: PaymentMethod.fromValue(map['payment_method'] as String?),
      paymentRef: map['payment_ref'] as String?,
      seller: map['seller'] is Map ? PersonRef.fromMap(map['seller']) : null,
      items: rawItems
          .whereType<Map>()
          .map((m) => OrderItem.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      subtotal: toInt(map['subtotal']),
      discount: toInt(map['discount']),
      total: toInt(map['total']),
      note: map['note']?.toString() ?? '',
      createdAt: toDate(map['created_at']),
      cancelledAt: toDate(map['cancelled_at']),
      cancelledBy: map['cancelled_by'] is Map
          ? PersonRef.fromMap(map['cancelled_by'])
          : null,
      cancelReason: map['cancel_reason'] as String?,
    );
  }

  factory Order.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromMap(doc.data() ?? const {}, id: doc.id);
}
