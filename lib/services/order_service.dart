import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:intl/intl.dart';

import '../core/enums.dart';
import '../core/firestore_paths.dart';
import '../models/order.dart';
import '../models/user_model.dart';
import '../providers/cart_provider.dart';

/// Tạo / hủy / truy vấn đơn hàng (L6, L9, L12).
class OrderService {
  OrderService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection(FsCollections.orders);

  /// Tạo đơn bán tại quán. Chạy trong một transaction:
  /// tăng `counters/orders_{yyyyMMdd}` → sinh `order_code` → ghi đơn.
  /// 2 máy bán cùng lúc không trùng mã; ghi lỗi thì counter không tăng.
  static Future<Order> createInStoreOrder({
    required CartProvider cart,
    required PaymentMethod method,
    required PersonRef seller,
    String? paymentRef,
  }) async {
    if (cart.isEmpty) throw StateError('Giỏ hàng trống');
    if (cart.fulfillment == Fulfillment.dineIn && cart.tableNumber == null) {
      throw StateError('Đơn tại quán phải chọn bàn');
    }

    // Chụp dữ liệu giỏ tại thời điểm này (Q5).
    final items = cart.items.map((i) => i.toOrderItem()).toList();
    final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotal);
    const discount = 0; // Chưa làm giảm giá (Q8).
    final total = subtotal - discount;
    final fulfillment = cart.fulfillment;
    final tableNumber =
        fulfillment == Fulfillment.dineIn ? cart.tableNumber : null;
    final note = cart.orderNote.trim();

    final now = DateTime.now();
    final counterRef = _db
        .collection(FsCollections.counters)
        .doc('orders_${DateFormat('yyyyMMdd').format(now)}');
    final orderRef = _orders.doc();

    final orderCode = await _db.runTransaction<String>((tx) async {
      final counterSnap = await tx.get(counterRef);
      final current = (counterSnap.data()?['seq'] as num?)?.toInt() ?? 0;
      final seq = current + 1;
      final code =
          '${DateFormat('ddMMyy').format(now)}-${seq.toString().padLeft(3, '0')}';

      tx.set(counterRef, {'seq': seq});
      tx.set(orderRef, {
        'order_code': code,
        'channel': OrderChannel.inStore.value,
        'fulfillment': fulfillment.value,
        'table_number': tableNumber,
        'status': OrderStatus.completed.value,
        'payment_status': PaymentStatus.paid.value,
        'payment_method': method.value,
        'payment_ref': ?paymentRef,
        'seller': seller.toMap(),
        'items': items.map((i) => i.toMap()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'note': note,
        'created_at': FieldValue.serverTimestamp(),
      });
      return code;
    });

    return Order(
      id: orderRef.id,
      orderCode: orderCode,
      channel: OrderChannel.inStore,
      fulfillment: fulfillment,
      tableNumber: tableNumber,
      status: OrderStatus.completed,
      paymentStatus: PaymentStatus.paid,
      paymentMethod: method,
      paymentRef: paymentRef,
      seller: seller,
      items: items,
      subtotal: subtotal,
      discount: discount,
      total: total,
      note: note,
      createdAt: now,
    );
  }

  /// Q7: admin hủy mọi đơn mọi lúc; nhân viên chỉ đơn của mình trong 30 phút.
  static bool canCancel(Order order, UserModel? user, {DateTime? now}) {
    if (user == null || order.status != OrderStatus.completed) return false;
    // Đơn online có quy trình hủy riêng (bước 7), không hủy kiểu tại quầy.
    if (order.isOnline) return false;
    if (user.isAdmin) return true;
    if (order.seller?.id != user.uid) return false;
    final created = order.createdAt;
    if (created == null) return false;
    return (now ?? DateTime.now()).difference(created) <=
        Order.staffCancelWindow;
  }

  /// Thời gian còn lại để nhân viên hủy (null nếu không áp dụng).
  static Duration? staffCancelRemaining(Order order, {DateTime? now}) {
    final created = order.createdAt;
    if (created == null) return null;
    final left =
        Order.staffCancelWindow - (now ?? DateTime.now()).difference(created);
    return left.isNegative ? Duration.zero : left;
  }

  /// Hủy đơn: chỉ đổi các trường hủy, không xóa doc (L9).
  static Future<void> cancelOrder({
    required Order order,
    required UserModel by,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw StateError('Vui lòng nhập lý do hủy');
    if (!canCancel(order, by)) {
      throw StateError(by.isAdmin
          ? 'Đơn này không thể hủy'
          : 'Đã quá 30 phút hoặc không phải đơn của bạn, liên hệ quản lý để hủy');
    }
    await _orders.doc(order.id).update({
      'status': OrderStatus.cancelled.value,
      'payment_status': PaymentStatus.refunded.value,
      'cancelled_at': FieldValue.serverTimestamp(),
      'cancelled_by': PersonRef(id: by.uid, name: by.name).toMap(),
      'cancel_reason': trimmed,
    });
  }

  /// Đơn online của một khách, mới nhất trước (Rules yêu cầu lọc đúng 2 điều kiện).
  static Stream<List<Order>> watchCustomerOrders(String uid, {int limit = 50}) => _orders
      .where('channel', isEqualTo: OrderChannel.online.value)
      .where('customer.id', isEqualTo: uid)
      .orderBy('created_at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Order.fromDoc).toList());

  static Stream<Order?> watchOrder(String id) => _orders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Order.fromDoc(d) : null);

  /// Đơn trong khoảng [from, to). Nhân viên chỉ thấy đơn của mình (sellerId).
  static Stream<List<Order>> watchOrders({
    required DateTime from,
    required DateTime to,
    String? sellerId,
  }) {
    Query<Map<String, dynamic>> q = _orders
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('created_at', isLessThan: Timestamp.fromDate(to));
    if (sellerId != null) q = q.where('seller.id', isEqualTo: sellerId);
    return q
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Order.fromDoc).toList());
  }
}
