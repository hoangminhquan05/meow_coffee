import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/formatters.dart';

/// Đơn vị hành chính: tỉnh/thành hoặc phường/xã.
class AdminUnit {
  final int code;
  final String name;

  const AdminUnit(this.code, this.name);

  Map<String, dynamic> toMap() => {'code': code, 'name': name};

  static AdminUnit? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    final name = raw['name'];
    if (code is! num || name is! String) return null;
    return AdminUnit(code.toInt(), name);
  }

  @override
  bool operator ==(Object other) => other is AdminUnit && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class Province extends AdminUnit {
  final List<AdminUnit> wards;

  const Province(super.code, super.name, this.wards);
}

/// Danh sách 34 tỉnh/thành và ~3.300 phường/xã (địa giới 2 cấp từ 1/7/2025),
/// đóng gói sẵn trong `assets/data/vn_admin_2025.json` – không cần mạng.
class VnAdminService {
  VnAdminService._();

  static List<Province>? _cache;

  static Future<List<Province>> provinces() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/vn_admin_2025.json');
    _cache = parse(raw);
    return _cache!;
  }

  /// Tách riêng để test được.
  static List<Province> parse(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final p in list.cast<Map<String, dynamic>>())
        Province(
          (p['c'] as num).toInt(),
          p['n'] as String,
          [
            for (final w in (p['w'] as List<dynamic>))
              AdminUnit(((w as List)[0] as num).toInt(), w[1] as String),
          ],
        ),
    ];
  }

  /// Lọc theo từ khóa, không phân biệt dấu ("tan dinh" ra "Phường Tân Định").
  static List<T> search<T extends AdminUnit>(List<T> units, String query) {
    final q = normalizeVietnamese(query.trim());
    if (q.isEmpty) return units;
    return units.where((u) => normalizeVietnamese(u.name).contains(q)).toList();
  }
}
