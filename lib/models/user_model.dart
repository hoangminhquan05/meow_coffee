class UserModel {
  final String uid;
  final String avtUrl;
  final String email;
  final String name;
  final String role;
  final String soDienThoai;

  const UserModel({
    this.uid = '',
    this.avtUrl = '',
    this.email = '',
    this.name = '',
    this.role = '',
    this.soDienThoai = '',
  });

  factory UserModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    return UserModel(
      uid: (map['uid'] as String?)?.isNotEmpty == true
          ? map['uid'] as String
          : (docId ?? ''),
      avtUrl: map['avtUrl'] as String? ?? '',
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? '',
      soDienThoai: map['soDienThoai'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'avtUrl': avtUrl,
      'email': email,
      'name': name,
      'role': role,
      'soDienThoai': soDienThoai,
    };
  }

  UserModel copyWith({
    String? uid,
    String? avtUrl,
    String? email,
    String? name,
    String? role,
    String? soDienThoai,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      avtUrl: avtUrl ?? this.avtUrl,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      soDienThoai: soDienThoai ?? this.soDienThoai,
    );
  }
}
