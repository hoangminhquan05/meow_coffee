import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum DistanceSource { osrm, haversine }

class DistanceResult {
  final double km;
  final DistanceSource source;

  const DistanceResult(this.km, this.source);

  /// "3,2 km" (ước tính thì thêm "~").
  String get label {
    final v = km.toStringAsFixed(1).replaceAll('.', ',');
    return source == DistanceSource.osrm ? '$v km' : '~$v km';
  }
}

/// Quãng đường đi thực tế qua OSRM (miễn phí, O8). Lỗi/quá chậm thì dùng
/// đường chim bay × 1.3. Kết quả được nhớ tạm theo cặp toạ độ.
class DistanceService {
  DistanceService._();

  static const roadFactor = 1.3;
  static const _osrmBase = 'https://router.project-osrm.org/route/v1/driving';
  static final _cache = <String, DistanceResult>{};
  static const _haversine = Distance();

  static String _key(LatLng a, LatLng b) =>
      '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)}'
      '|${b.latitude.toStringAsFixed(5)},${b.longitude.toStringAsFixed(5)}';

  /// Đường chim bay × 1.3 (km).
  static double estimateKm(LatLng a, LatLng b) =>
      _haversine.as(LengthUnit.Meter, a, b) / 1000 * roadFactor;

  /// Kết quả đã tính trước đó (để hiển thị ngay, không nháy "Đang tính").
  static DistanceResult? cached(LatLng from, LatLng to) => _cache[_key(from, to)];

  static Future<DistanceResult> road(LatLng from, LatLng to) async {
    final key = _key(from, to);
    final cached = _cache[key];
    if (cached != null) return cached;

    DistanceResult result;
    try {
      // OSRM nhận toạ độ dạng lng,lat.
      final uri = Uri.parse(
        '$_osrmBase/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}?overview=false',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (res.statusCode != 200 || body['code'] != 'Ok' || routes == null || routes.isEmpty) {
        throw StateError('OSRM ${res.statusCode} ${body['code']}');
      }
      final meters = ((routes.first as Map)['distance'] as num).toDouble();
      result = DistanceResult(meters / 1000, DistanceSource.osrm);
    } catch (e) {
      debugPrint('DistanceService OSRM failed, fallback to haversine: $e');
      result = DistanceResult(estimateKm(from, to), DistanceSource.haversine);
    }
    _cache[key] = result;
    return result;
  }
}
