import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../services/vn_admin_service.dart';

enum AddressLabel {
  home('home', 'Nhà'),
  work('work', 'Công ty'),
  other('other', 'Khác');

  const AddressLabel(this.value, this.text);
  final String value;
  final String text;

  static AddressLabel fromValue(String? raw) => AddressLabel.values
      .firstWhere((e) => e.value == raw, orElse: () => AddressLabel.other);
}

/// Địa chỉ giao hàng trong `users/{uid}/addresses/{id}` (O7).
class Address {
  /// Mỗi khách lưu tối đa 3 địa chỉ.
  static const maxPerUser = 3;

  final String id;
  final AddressLabel label;
  final String receiverName;
  final String receiverPhone;
  final AdminUnit province;
  final AdminUnit ward;
  final String street;
  final String note;
  final LatLng location;
  final bool isDefault;
  final DateTime? createdAt;

  const Address({
    this.id = '',
    required this.label,
    required this.receiverName,
    required this.receiverPhone,
    required this.province,
    required this.ward,
    required this.street,
    this.note = '',
    required this.location,
    this.isDefault = false,
    this.createdAt,
  });

  /// "12 Lê Lợi, Phường Bến Thành, Thành phố Hồ Chí Minh".
  String get fullText => [street, ward.name, province.name]
      .where((s) => s.trim().isNotEmpty)
      .join(', ');

  static Address? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    if (m == null) return null;
    final province = AdminUnit.fromMap(m['province']);
    final ward = AdminUnit.fromMap(m['ward']);
    final loc = m['location'];
    if (province == null || ward == null || loc is! Map) return null;
    final lat = loc['lat'], lng = loc['lng'];
    if (lat is! num || lng is! num) return null;
    final created = m['created_at'];
    return Address(
      id: doc.id,
      label: AddressLabel.fromValue(m['label'] as String?),
      receiverName: m['receiver_name'] as String? ?? '',
      receiverPhone: m['receiver_phone'] as String? ?? '',
      province: province,
      ward: ward,
      street: m['street'] as String? ?? '',
      note: m['note'] as String? ?? '',
      location: LatLng(lat.toDouble(), lng.toDouble()),
      isDefault: m['is_default'] as bool? ?? false,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  /// Dữ liệu ghi Firestore (không gồm is_default, created_at).
  Map<String, dynamic> toMap() => {
        'label': label.value,
        'receiver_name': receiverName,
        'receiver_phone': receiverPhone,
        'province': province.toMap(),
        'ward': ward.toMap(),
        'street': street,
        'note': note,
        'location': {'lat': location.latitude, 'lng': location.longitude},
      };
}
