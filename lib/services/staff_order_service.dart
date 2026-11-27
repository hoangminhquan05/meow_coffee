import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../core/enums.dart';
import '../core/firestore_paths.dart';
import '../models/order.dart';
import '../models/shipper_status.dart';

/// NV/admin xử lý đơn online (bước 7): xác nhận, từ chối/hủy, pha chế, bỏ món,
/// và admin đánh dấu đã hoàn tiền. Ghi thẳng Firestore trong transaction
/// (Rules kiểm đúng trạng thái nguồn → đích, xem firestore.rules).
class StaffOrderService {
  StaffOrderService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection(FsCollections.orders);

  /// Trạng thái hiện trên màn "Đơn online".
  static const activeStatuses = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.delivering,
    OrderStatus.deliveryFailed,
  ];

  /// Quán được hủy đơn khi shipper chưa lấy hàng.
  static const shopCancellable = {
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
  };

  /// Bỏ món được khi chưa pha xong.
  static const itemEditable = {
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
  };

  /// Bước kế tiếp do NV bấm (xác nhận → bắt đầu pha → pha xong).
  static const nextStep = {
    OrderStatus.pending: OrderStatus.confirmed,
    OrderStatus.confirmed: OrderStatus.preparing,
    OrderStatus.preparing: OrderStatus.ready,
  };

  static const rejectReasons = [
    'Hết món',
    'Quán quá tải',
    'Không liên lạc được khách',
    'Sắp đóng cửa',
    'Khác',
  ];

  static const removeReasons = ['Hết món', 'Khách đổi ý', 'Khác'];

  /// Đơn online đang xử lý, cũ nhất trước (làm trước).
  static Stream<List<Order>> watchActive() => _orders
      .where('channel', isEqualTo: OrderChannel.online.value)
      .where('status', whereIn: activeStatuses.map((s) => s.value).toList())
      .snapshots()
      .map((s) => s.docs.map(Order.fromDoc).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(2100))
            .compareTo(b.createdAt ?? DateTime(2100))));

  /// Đơn online giao thành công trong ngày `day` (mới giao nhất trước).
  /// Lọc theo `delivery.done_day` (Worker ghi khi shipper bấm Đã giao).
  static Stream<List<Order>> watchDeliveredOn(DateTime day) => _orders
      .where('channel', isEqualTo: OrderChannel.online.value)
      .where('status', isEqualTo: OrderStatus.completed.value)
      .where('delivery.done_day', isEqualTo: ShipperStatus.dayKey(day))
      .snapshots()
      .map((s) => s.docs.map(Order.fromDoc).toList()
        ..sort((a, b) => (b.delivery?.deliveredAt ?? DateTime(0))
            .compareTo(a.delivery?.deliveredAt ?? DateTime(0))));

  /// Đơn còn phải hoàn tiền (chỉ admin đọc được hết).
  static Stream<List<Order>> watchPendingRefunds() => _orders
      .where('refund.required', isEqualTo: true)
      .where('refund.done', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map(Order.fromDoc).toList()
        ..sort((a, b) => (b.cancelledAt ?? b.createdAt ?? DateTime(0))
            .compareTo(a.cancelledAt ?? a.createdAt ?? DateTime(0))));

  static Map<String, dynamic> _by(PersonRef by, String role) =>
      {'id': by.id, 'name': by.name, 'role': role};

  static Map<String, dynamic> _history(
          OrderStatus status, PersonRef by, String role) =>
      {'status': status.value, 'at': Timestamp.now(), 'by': _by(by, role)};

  /// Đọc đơn trong transaction và kiểm trạng thái hiện tại.
  static Future<Order> _load(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> ref,
    Set<OrderStatus> allowed,
    String message,
  ) async {
    final snap = await tx.get(ref);
    if (!snap.exists) throw StateError('Không tìm thấy đơn');
    final order = Order.fromDoc(snap);
    if (!order.isOnline) throw StateError('Không phải đơn online');
    if (!allowed.contains(order.status)) {
      throw StateError('$message (đơn đang ở "${order.status.label}")');
    }
    return order;
  }

  /// Chuyển sang bước kế tiếp: Chờ xác nhận → Đã xác nhận → Đang pha → Chờ giao.
  static Future<void> advance({
    required String orderId,
    required OrderStatus from,
    required PersonRef by,
    required String role,
  }) async {
    final to = nextStep[from];
    if (to == null) throw StateError('Không có bước tiếp theo');
    final ref = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      await _load(tx, ref, {from}, 'Đơn vừa được người khác cập nhật');
      tx.update(ref, {
        'status': to.value,
        'status_history': FieldValue.arrayUnion([_history(to, by, role)]),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Quán từ chối (lúc Chờ xác nhận) hoặc hủy đơn (trước khi shipper lấy hàng).
  /// Đơn đã trả trước → ghi cần hoàn tiền (O17, O32).
  static Future<void> cancelByShop({
    required String orderId,
    required String reason,
    required PersonRef by,
    required String role,
  }) async {
    final text = reason.trim();
    if (text.isEmpty) throw StateError('Vui lòng chọn lý do');
    final ref = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final order = await _load(
          tx, ref, shopCancellable, 'Không thể hủy đơn ở trạng thái này');
      final paid = order.paymentStatus == PaymentStatus.paid;
      final owed = order.refund?.isPending == true ? order.refund!.amount : 0;
      tx.update(ref, {
        'status': OrderStatus.cancelled.value,
        'status_history': FieldValue.arrayUnion(
            [_history(OrderStatus.cancelled, by, role)]),
        'cancelled_at': FieldValue.serverTimestamp(),
        'cancelled_by': _by(by, role),
        'cancel_reason': text,
        'updated_at': FieldValue.serverTimestamp(),
        if (paid) ...{
          'payment_status': PaymentStatus.refunded.value,
          'refund': {
            'required': true,
            'amount': owed + order.total,
            'done': false,
          },
        },
      });
    });
  }

  /// Bỏ `quantity` ly của dòng `index` (bỏ hết = xóa dòng). Không được bỏ món
  /// cuối cùng – muốn bỏ hết thì hủy đơn. Đơn đã trả trước → cộng phần chênh
  /// vào số cần hoàn.
  static Future<void> removeItem({
    required String orderId,
    required int index,
    required int quantity,
    required String reason,
    required PersonRef by,
    required String role,
  }) async {
    final text = reason.trim();
    if (text.isEmpty) throw StateError('Vui lòng chọn lý do');
    final ref = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final order = await _load(
          tx, ref, itemEditable, 'Không thể bỏ món ở trạng thái này');
      if (index < 0 || index >= order.items.length) {
        throw StateError('Món không còn trong đơn');
      }
      final item = order.items[index];
      if (quantity < 1 || quantity > item.quantity) {
        throw StateError('Số lượng bỏ không hợp lệ');
      }
      final items = [...order.items];
      if (quantity == item.quantity) {
        items.removeAt(index);
      } else {
        items[index] = OrderItem(
          productId: item.productId,
          name: item.name,
          category: item.category,
          size: item.size,
          unitPrice: item.unitPrice,
          quantity: item.quantity - quantity,
          note: item.note,
        );
      }
      if (items.isEmpty) {
        throw StateError('Không thể bỏ món cuối cùng – hãy hủy đơn');
      }
      final removedAmount = item.unitPrice * quantity;
      final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotal);
      final total = subtotal - order.discount + order.deliveryFee;
      final paid = order.paymentStatus == PaymentStatus.paid;
      final owed = order.refund?.isPending == true ? order.refund!.amount : 0;
      tx.update(ref, {
        'items': items.map((i) => i.toMap()).toList(),
        'subtotal': subtotal,
        'total': total,
        'item_changes': FieldValue.arrayUnion([
          {
            'at': Timestamp.now(),
            'by': _by(by, role),
            'removed': {
              'product_id': item.productId,
              'name': item.name,
              'size': item.size,
              'quantity': quantity,
              'line_total': removedAmount,
            },
            'reason': text,
          }
        ]),
        'updated_at': FieldValue.serverTimestamp(),
        if (paid)
          'refund': {
            'required': true,
            'amount': owed + (order.total - total),
            'done': false,
          },
      });
    });
  }

  /// Admin đã chuyển khoản hoàn tiền cho khách.
  static Future<void> markRefunded({
    required String orderId,
    required String note,
    required PersonRef by,
  }) async {
    final ref = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final order = snap.exists ? Order.fromDoc(snap) : null;
      final refund = order?.refund;
      if (refund == null || !refund.isPending) {
        throw StateError('Đơn này không còn cần hoàn tiền');
      }
      tx.update(ref, {
        'refund': {
          'required': true,
          'amount': refund.amount,
          'done': true,
          'done_by': by.toMap(),
          'done_at': FieldValue.serverTimestamp(),
          'note': note.trim(),
        },
      });
    });
  }
}
