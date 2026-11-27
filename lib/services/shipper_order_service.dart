import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:latlong2/latlong.dart';

import '../core/firestore_paths.dart';
import '../models/order.dart';
import '../models/shipper_status.dart';
import 'online_order_service.dart';

/// Shipper nhận lời mời và giao đơn (bước 9). Mọi thao tác đi qua Worker
/// (`POST /dispatch/{id}/respond`, `POST /shipper/orders/{id}`) để cập nhật
/// đơn + trạng thái shipper + nhật ký lời mời cùng lúc.
class ShipperOrderService {
  ShipperOrderService._();

  static CollectionReference<Map<String, dynamic>> get _orders =>
      FirebaseFirestore.instance.collection(FsCollections.orders);

  static const failReasons = [
    'Không liên lạc được khách',
    'Khách không có nhà',
    'Sai địa chỉ',
    'Khách từ chối nhận hàng',
    'Khác',
  ];

  static Stream<Order?> watchOrder(String id) =>
      _orders.doc(id).snapshots().map((d) => d.exists ? Order.fromDoc(d) : null);

  /// Đơn đã giao xong hôm nay của shipper.
  static Stream<List<Order>> watchDoneToday(String uid, DateTime now) => _orders
      .where('delivery.shipper.id', isEqualTo: uid)
      .where('delivery.done_day', isEqualTo: ShipperStatus.dayKey(now))
      .snapshots()
      .map((s) => s.docs.map(Order.fromDoc).toList()
        ..sort((a, b) => (b.delivery?.deliveredAt ?? DateTime(0))
            .compareTo(a.delivery?.deliveredAt ?? DateTime(0))));

  /// Trả lời lời mời: `accept` | `decline` | `timeout`. Trả về cảnh báo (O35) nếu có.
  static Future<String?> respond({
    required String orderId,
    required String offerId,
    required String action,
  }) async {
    final res = await OnlineOrderService.post(
      '/dispatch/$orderId/respond',
      {'offer_id': offerId, 'action': action},
      okStatus: 200,
    );
    return res['warning'] as String?;
  }

  static Future<Map<String, dynamic>> _act(String orderId, Map<String, dynamic> body) =>
      OnlineOrderService.post('/shipper/orders/$orderId', body, okStatus: 200);

  static Future<void> pickedUp(String orderId) => _act(orderId, {'action': 'picked_up'});
  static Future<void> arrived(String orderId) => _act(orderId, {'action': 'arrived'});
  static Future<void> called(String orderId) => _act(orderId, {'action': 'call'});
  static Future<void> delivered(String orderId, {required bool collected}) =>
      _act(orderId, {'action': 'delivered', 'collected': collected});
  static Future<void> failed(String orderId, String reason) =>
      _act(orderId, {'action': 'failed', 'reason': reason});

  /// Thứ tự giao gợi ý: lộ trình ngắn nhất từ quán qua các điểm giao (≤ 3 điểm
  /// nên thử mọi hoán vị). Đơn thiếu tọa độ để cuối.
  static List<Order> suggestRoute(LatLng? start, List<Order> orders) {
    final withLoc = orders.where((o) => o.delivery?.location != null).toList();
    final rest = orders.where((o) => o.delivery?.location == null).toList();
    if (start == null || withLoc.length < 2 || withLoc.length > 5) return [...withLoc, ...rest];
    const d = Distance();
    List<Order> best = withLoc;
    var bestKm = double.infinity;
    for (final perm in _permutations(withLoc)) {
      var km = 0.0;
      var at = start;
      for (final o in perm) {
        km += d.as(LengthUnit.Meter, at, o.delivery!.location!);
        at = o.delivery!.location!;
      }
      if (km < bestKm) {
        bestKm = km;
        best = perm;
      }
    }
    return [...best, ...rest];
  }

  static Iterable<List<T>> _permutations<T>(List<T> xs) sync* {
    if (xs.length <= 1) {
      yield xs;
      return;
    }
    for (var i = 0; i < xs.length; i++) {
      final rest = [...xs]..removeAt(i);
      for (final p in _permutations(rest)) {
        yield [xs[i], ...p];
      }
    }
  }

  /// Phút còn phải chờ trước khi được bấm "Giao không thành công" (0 = được).
  static int minutesLeft(DateTime? arrivedAt, int waitMinutes, DateTime now) {
    if (arrivedAt == null) return waitMinutes;
    final waited = now.difference(arrivedAt).inSeconds / 60;
    return math.max(0, (waitMinutes - waited).ceil());
  }
}
