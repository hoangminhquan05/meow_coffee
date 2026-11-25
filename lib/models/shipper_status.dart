import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// `shipper_status/{uid}` – trạng thái ca + vị trí của shipper (bước 8).
class ShipperStatus {
  final String uid;
  final String name;
  final String phone;
  final bool onShift;
  final DateTime? shiftStartedAt;
  final LatLng? location;
  final DateTime? locationUpdatedAt;
  final List<String> activeOrderIds;
  final int codHolding;
  final int shiftDeclines;

  const ShipperStatus({
    required this.uid,
    required this.name,
    required this.phone,
    required this.onShift,
    this.shiftStartedAt,
    this.location,
    this.locationUpdatedAt,
    this.activeOrderIds = const [],
    this.codHolding = 0,
    this.shiftDeclines = 0,
  });

  static const offShift = ShipperStatus(uid: '', name: '', phone: '', onShift: false);

  /// Vị trí cũ hơn chừng này phút coi như không có (O20).
  static const staleAfter = Duration(minutes: 10);

  bool isLocationStale(DateTime now) =>
      locationUpdatedAt == null || now.difference(locationUpdatedAt!) > staleAfter;

  factory ShipperStatus.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final loc = m['location'];
    final shipper = m['shipper'] is Map ? m['shipper'] as Map : const {};
    return ShipperStatus(
      uid: doc.id,
      name: shipper['name']?.toString() ?? '',
      phone: shipper['phone']?.toString() ?? '',
      onShift: m['on_shift'] == true,
      shiftStartedAt: ts(m['shift_started_at']),
      location: loc is Map && loc['lat'] is num && loc['lng'] is num
          ? LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble())
          : null,
      locationUpdatedAt: ts(m['location_updated_at']),
      activeOrderIds: (m['active_order_ids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      codHolding: (m['cod_holding'] as num?)?.round() ?? 0,
      shiftDeclines: (m['shift_declines'] as num?)?.round() ?? 0,
    );
  }
}
