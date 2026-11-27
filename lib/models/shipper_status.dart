import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// `shipper_status/{uid}` – trạng thái ca + vị trí của shipper (bước 8).
class ShipperStatus {
  final String uid;
  final String name;
  final String phone;
  final bool onShift;
  final String shiftId;
  final DateTime? shiftStartedAt;
  final LatLng? location;
  final DateTime? locationUpdatedAt;
  final List<String> activeOrderIds;
  final int codHolding;
  final int shiftDeclines;
  final PendingOffer? pendingOffer;
  final String statsDay;
  final int deliveredTodayRaw;
  final int failedTodayRaw;

  const ShipperStatus({
    required this.uid,
    required this.name,
    required this.phone,
    required this.onShift,
    this.shiftId = '',
    this.shiftStartedAt,
    this.location,
    this.locationUpdatedAt,
    this.activeOrderIds = const [],
    this.codHolding = 0,
    this.shiftDeclines = 0,
    this.pendingOffer,
    this.statsDay = '',
    this.deliveredTodayRaw = 0,
    this.failedTodayRaw = 0,
  });

  /// "20261127" theo giờ máy (VN), giống Worker vnDayKey.
  static String dayKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  int deliveredToday(DateTime now) => statsDay == dayKey(now) ? deliveredTodayRaw : 0;
  int failedToday(DateTime now) => statsDay == dayKey(now) ? failedTodayRaw : 0;

  /// Lời mời còn hạn (null nếu không có / đã hết giờ).
  PendingOffer? liveOffer(DateTime now) {
    final p = pendingOffer;
    if (p == null || p.expiresAt == null || !p.expiresAt!.isAfter(now)) return null;
    return p;
  }

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
      shiftId: m['shift_id']?.toString() ?? '',
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
      pendingOffer: m['pending_offer'] is Map
          ? PendingOffer.fromMap(Map<String, dynamic>.from(m['pending_offer']))
          : null,
      statsDay: m['stats_day']?.toString() ?? '',
      deliveredTodayRaw: (m['delivered_today'] as num?)?.round() ?? 0,
      failedTodayRaw: (m['failed_today'] as num?)?.round() ?? 0,
    );
  }
}

/// `shipper_status.pending_offer` – lời mời giao đơn đang chờ trả lời.
class PendingOffer {
  final String orderId;
  final String orderCode;
  final String offerId;
  final DateTime? expiresAt;

  const PendingOffer({
    required this.orderId,
    required this.orderCode,
    required this.offerId,
    this.expiresAt,
  });

  factory PendingOffer.fromMap(Map<String, dynamic> m) {
    final exp = m['expires_at'];
    return PendingOffer(
      orderId: m['order_id']?.toString() ?? '',
      orderCode: m['order_code']?.toString() ?? '',
      offerId: m['offer_id']?.toString() ?? '',
      expiresAt: exp is Timestamp ? exp.toDate() : null,
    );
  }
}
