import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mở trình gọi điện với số đã điền sẵn (O29 – không gọi trong app).
Future<bool> openDialer(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  return launchUrl(Uri(scheme: 'tel', path: digits));
}

/// Mở Google Maps chỉ đường tới tọa độ (app Maps nếu có, không thì trình duyệt).
Future<bool> openDirections(LatLng to) => launchUrl(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${to.latitude},${to.longitude}',
        'travelmode': 'two-wheeler',
      }),
      mode: LaunchMode.externalApplication,
    );
