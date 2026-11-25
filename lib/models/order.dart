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

  // ---- Đơn online (channel = online) ----
  final OrderCustomer? customer;
  final OrderDelivery? delivery;
  final List<StatusEntry> statusHistory;

  /// Hạn chuyển khoản VietQR (đơn `awaiting_payment`).
  final DateTime? paymentExpiresAt;

  /// Món quán đã bỏ khỏi đơn (O16).
  final List<ItemChange> itemChanges;

  /// Hoàn tiền thủ công cho đơn đã trả trước (O32); null nếu không cần.
  final OrderRefund? refund;

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
    this.customer,
    this.delivery,
    this.statusHistory = const [],
    this.paymentExpiresAt,
    this.itemChanges = const [],
    this.refund,
  });

  /// Phí giao hàng (0 nếu không phải đơn giao).
  int get deliveryFee => delivery?.fee ?? 0;

  bool get isCancelled => status == OrderStatus.cancelled;
  bool get isOnline => channel == OrderChannel.online;

  /// Nội dung chuyển khoản VietQR: mã đơn bỏ dấu gạch ("ON231126005").
  String get transferContent => orderCode.replaceAll('-', '');

  /// Thời điểm đơn chuyển sang trạng thái `s` (lần gần nhất), nếu có.
  DateTime? timeOf(OrderStatus s) {
    for (final e in statusHistory.reversed) {
      if (e.status == s) return e.at;
    }
    return null;
  }

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
      customer: map['customer'] is Map
          ? OrderCustomer.fromMap(Map<String, dynamic>.from(map['customer']))
          : null,
      delivery: map['delivery'] is Map
          ? OrderDelivery.fromMap(Map<String, dynamic>.from(map['delivery']))
          : null,
      statusHistory: (map['status_history'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => StatusEntry.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      paymentExpiresAt: map['payment'] is Map
          ? toDate((map['payment'] as Map)['expires_at'])
          : null,
      itemChanges: (map['item_changes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => ItemChange.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      refund: map['refund'] is Map
          ? OrderRefund.fromMap(Map<String, dynamic>.from(map['refund']))
          : null,
    );
  }

  factory Order.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Order.fromMap(doc.data() ?? const {}, id: doc.id);
}

class OrderCustomer {
  final String id;
  final String name;
  final String phone;

  const OrderCustomer({required this.id, required this.name, required this.phone});

  factory OrderCustomer.fromMap(Map<String, dynamic> m) => OrderCustomer(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        phone: m['phone']?.toString() ?? '',
      );
}

/// Thông tin giao hàng chụp lúc đặt đơn (Worker ghi).
class OrderDelivery {
  final String receiverName;
  final String receiverPhone;
  final String addressText;
  final String note;
  final double distanceKm;
  final bool distanceEstimated;
  final int fee;
  final PersonRef? shipper;
  final String? shipperPhone;

  const OrderDelivery({
    required this.receiverName,
    required this.receiverPhone,
    required this.addressText,
    required this.note,
    required this.distanceKm,
    required this.distanceEstimated,
    required this.fee,
    this.shipper,
    this.shipperPhone,
  });

  factory OrderDelivery.fromMap(Map<String, dynamic> m) {
    final shipper = m['shipper'];
    return OrderDelivery(
      receiverName: m['receiver_name']?.toString() ?? '',
      receiverPhone: m['receiver_phone']?.toString() ?? '',
      addressText: m['address_text']?.toString() ?? '',
      note: m['note']?.toString() ?? '',
      distanceKm: (m['distance_km'] as num?)?.toDouble() ?? 0,
      distanceEstimated: m['distance_source'] == 'haversine',
      fee: (m['fee'] as num?)?.round() ?? 0,
      shipper: shipper is Map ? PersonRef.fromMap(shipper) : null,
      shipperPhone: shipper is Map ? shipper['phone']?.toString() : null,
    );
  }
}

class StatusEntry {
  final OrderStatus status;
  final DateTime? at;
  final String byRole;
  final String byName;

  const StatusEntry({
    required this.status,
    required this.at,
    required this.byRole,
    this.byName = '',
  });

  factory StatusEntry.fromMap(Map<String, dynamic> m) {
    final at = m['at'];
    final by = m['by'];
    return StatusEntry(
      status: OrderStatus.fromValue(m['status'] as String?),
      at: at is Timestamp ? at.toDate() : null,
      byRole: by is Map ? (by['role']?.toString() ?? '') : '',
      byName: by is Map ? (by['name']?.toString() ?? '') : '',
    );
  }
}

/// Một lần quán bỏ món (cả dòng hoặc bớt số lượng) – O16.
class ItemChange {
  final DateTime? at;
  final PersonRef by;
  final String name;
  final String size;
  final int quantity;
  final int amount;
  final String reason;

  const ItemChange({
    required this.at,
    required this.by,
    required this.name,
    required this.size,
    required this.quantity,
    required this.amount,
    required this.reason,
  });

  String get displayName =>
      size == Product.defaultSize ? name : '$name ($size)';

  factory ItemChange.fromMap(Map<String, dynamic> m) {
    final removed = m['removed'] is Map ? m['removed'] as Map : const {};
    final at = m['at'];
    return ItemChange(
      at: at is Timestamp ? at.toDate() : null,
      by: PersonRef.fromMap(m['by']),
      name: removed['name']?.toString() ?? '',
      size: removed['size']?.toString() ?? Product.defaultSize,
      quantity: (removed['quantity'] as num?)?.round() ?? 0,
      amount: (removed['line_total'] as num?)?.round() ?? 0,
      reason: m['reason']?.toString() ?? '',
    );
  }
}

/// Hoàn tiền thủ công (O32): `amount` là số còn phải hoàn khi `done = false`.
class OrderRefund {
  final bool required;
  final int amount;
  final bool done;
  final PersonRef? doneBy;
  final DateTime? doneAt;
  final String note;

  const OrderRefund({
    required this.required,
    required this.amount,
    required this.done,
    this.doneBy,
    this.doneAt,
    this.note = '',
  });

  bool get isPending => required && !done;

  factory OrderRefund.fromMap(Map<String, dynamic> m) {
    final at = m['done_at'];
    return OrderRefund(
      required: m['required'] == true,
      amount: (m['amount'] as num?)?.round() ?? 0,
      done: m['done'] == true,
      doneBy: m['done_by'] is Map ? PersonRef.fromMap(m['done_by']) : null,
      doneAt: at is Timestamp ? at.toDate() : null,
      note: m['note']?.toString() ?? '',
    );
  }
}
