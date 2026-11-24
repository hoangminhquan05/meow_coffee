import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import 'meow_ui.dart';

/// Tâm bản đồ mặc định khi chưa có vị trí (Hồ Gươm, Hà Nội).
const _defaultCenter = LatLng(21.0285, 105.8542);

/// Lớp bản đồ OpenStreetMap dùng chung (miễn phí, không cần API key).
/// Dùng tên miền phụ `tile.osm.org` vì một số mạng tại VN không phân giải được
/// `tile.openstreetmap.org` (bản đồ hiện ô xám). Lỗi thì lấy từ máy chủ
/// OSM Đức. (CARTO đã yêu cầu API key nên không dùng.)
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.osm.org/{z}/{x}/{y}.png',
      fallbackUrl: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
      maxZoom: 19,
      userAgentPackageName: 'vn.meowcoffee.dacn2',
    );

/// Ghi công nguồn bản đồ (bắt buộc theo điều khoản sử dụng của OSM).
const mapAttribution = RichAttributionWidget(
  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
);

/// Mở màn ghim vị trí; trả về toạ độ đã chọn hoặc null nếu hủy.
Future<LatLng?> pickLocationOnMap(
  BuildContext context, {
  LatLng? initial,
  String title = 'Ghim vị trí',
}) {
  return Navigator.push<LatLng>(
    context,
    MaterialPageRoute(
      builder: (_) => MapLocationPickerScreen(initial: initial, title: title),
    ),
  );
}

/// Kéo bản đồ để ghim nằm đúng vị trí; nút GPS đưa về vị trí hiện tại.
class MapLocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  final String title;

  const MapLocationPickerScreen({super.key, this.initial, required this.title});

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final _mapController = MapController();
  late LatLng _center = widget.initial ?? _defaultCenter;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Chưa có vị trí → thử lấy GPS ngay để đỡ phải kéo xa.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToMyLocation());
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController.move(here, 17);
      setState(() => _center = here);
    } on LocationError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(title: widget.title),
      // Bản đồ chiếm phần trên; thanh xác nhận nằm riêng bên dưới để không
      // che nút GPS và phần ghi công nguồn bản đồ.
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: widget.initial == null ? 13 : 17,
                    onPositionChanged: (camera, _) =>
                        setState(() => _center = camera.center),
                  ),
                  children: [
                    osmTileLayer(),
                    mapAttribution,
                  ],
                ),
                // Ghim cố định giữa bản đồ; mũi ghim chạm đúng tâm.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: Icon(Icons.location_on,
                          size: 44, color: AppColors.danger),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'gps',
                    tooltip: 'Vị trí hiện tại',
                    backgroundColor: AppColors.surface,
                    onPressed: _locating ? null : _goToMyLocation,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, color: AppColors.brand),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kéo bản đồ để ghim nằm đúng vị trí · '
                      '${_center.latitude.toStringAsFixed(6)}, '
                      '${_center.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    MeowPrimaryButton(
                      label: 'Xác nhận vị trí này',
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.pop(context, _center),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocationError implements Exception {
  final String message;
  const LocationError(this.message);
}

/// Lấy vị trí GPS hiện tại, xin quyền nếu cần. Lỗi → [LocationError] tiếng Việt.
Future<Position> getCurrentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationError('Vui lòng bật dịch vụ vị trí (GPS) trên máy');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationError('Bạn chưa cho phép app dùng vị trí');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationError(
      'Quyền vị trí đã bị chặn, hãy mở Cài đặt máy để cho phép',
    );
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

/// Bản đồ nhỏ chỉ xem (không kéo), có ghim ở vị trí cho trước.
class MapPreview extends StatelessWidget {
  final LatLng location;
  final double height;

  const MapPreview({super.key, required this.location, this.height = 160});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          key: ValueKey(location),
          options: MapOptions(
            initialCenter: location,
            initialZoom: 16,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            osmTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: location,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(
                    Icons.location_on,
                    size: 40,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap',
                  style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}
