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

  const UserModel({
    this.uid = '',
    this.name = '',
    this.email = '',
    this.phone = '',
    this.role = UserRole.staff,
    this.avtUrl = '',
    this.isActive = true,
    this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;

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
    );
  }
}
