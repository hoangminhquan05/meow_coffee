import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../core/firestore_paths.dart';
import '../models/shipper_status.dart';
import 'online_order_service.dart';

/// Ca làm việc + GPS của shipper (bước 8).
/// Vào/ra ca qua Worker (`POST /shipper/shift`); vị trí trong ca ghi thẳng
/// `shipper_status/{uid}` (Rules chỉ cho đổi vị trí).
class ShipperService {
  ShipperService._();

  /// Chu kỳ gửi GPS khi app đang mở (O20).
  static const gpsInterval = Duration(seconds: 30);

  static CollectionReference<Map<String, dynamic>> get _status =>
      FirebaseFirestore.instance.collection(FsCollections.shipperStatus);

  static Stream<ShipperStatus> watchMine(String uid) => _status.doc(uid).snapshots().map(
      (d) => d.exists ? ShipperStatus.fromDoc(d) : ShipperStatus.offShift);

  /// Shipper đang trong ca (NV/admin xem).
  static Stream<List<ShipperStatus>> watchOnShift() => _status
      .where('on_shift', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(ShipperStatus.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  static Future<void> startShift(LatLng location) => OnlineOrderService.post(
        '/shipper/shift',
        {
          'action': 'start',
          'location': {'lat': location.latitude, 'lng': location.longitude},
        },
        okStatus: 200,
      );

  static Future<void> endShift() =>
      OnlineOrderService.post('/shipper/shift', {'action': 'end'}, okStatus: 200);

  static Future<void> sendLocation(String uid, LatLng location) => _status.doc(uid).update({
        'location': {'lat': location.latitude, 'lng': location.longitude},
        'location_updated_at': FieldValue.serverTimestamp(),
      });
}
