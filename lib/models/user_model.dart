import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';

/// Người dùng trong `users/{uid}` (docId = Firebase Auth uid).
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String avtUrl;
  final bool isActive;
  final DateTime? createdAt;

  /// SĐT dạng quốc tế (+84…), dùng để đối chiếu với SĐT đã xác minh OTP.
  final String phoneE164;
  final bool phoneVerified;
  final bool emailVerified;

  const UserModel({
    this.uid = '',
    this.name = '',
    this.email = '',
    this.phone = '',
    this.role = UserRole.staff,
    this.avtUrl = '',
    this.isActive = true,
    this.createdAt,
    this.phoneE164 = '',
    this.phoneVerified = false,
    this.emailVerified = false,
  });

  bool get isAdmin => role == UserRole.admin;

  /// Khách được đặt đơn online khi đã xác minh SĐT hoặc email (O2).
  bool get isVerified => phoneVerified || emailVerified;

  factory UserModel.fromMap(Map<String, dynamic> map, {required String uid}) {
    final created = map['created_at'];
    return UserModel(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      role: UserRole.fromValue(map['role'] as String?),
      avtUrl: map['avt_url'] as String? ?? '',
      isActive: map['is_active'] as bool? ?? true,
      createdAt: created is Timestamp ? created.toDate() : null,
      phoneE164: map['phone_e164'] as String? ?? '',
      phoneVerified: map['phone_verified'] as bool? ?? false,
      emailVerified: map['email_verified'] as bool? ?? false,
    );
  }

  factory UserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserModel.fromMap(doc.data() ?? const {}, uid: doc.id);

  /// Dữ liệu ghi Firestore (không gồm `created_at`).
  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role.value,
        'avt_url': avtUrl,
        'is_active': isActive,
      };

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    String? avtUrl,
    bool? isActive,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      avtUrl: avtUrl ?? this.avtUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      phoneE164: phoneE164,
      phoneVerified: phoneVerified,
      emailVerified: emailVerified,
    );
  }
}
