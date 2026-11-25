import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/shipper_status.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/shipper_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/meow_ui.dart';
import 'online_orders_screen.dart' show timeAgo;

/// NV/admin xem shipper đang trong ca: bản đồ vị trí + danh sách (bước 8).
class ShippersLiveScreen extends StatefulWidget {
  const ShippersLiveScreen({super.key});

  @override
  State<ShippersLiveScreen> createState() => _ShippersLiveScreenState();
}

class _ShippersLiveScreenState extends State<ShippersLiveScreen> {
  late final Stream<List<ShipperStatus>> _stream = ShipperService.watchOnShift();
  final _map = MapController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopSettingsProvider>().settings.location;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Shipper Đang Làm'),
      body: StreamBuilder<List<ShipperStatus>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Lỗi tải: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final list = snap.data!;
          final now = DateTime.now();
          final center = shop ??
              list.map((s) => s.location).whereType<LatLng>().firstOrNull ??
              const LatLng(16.0544, 108.2022);

          return Column(
            children: [
              SizedBox(
                height: 280,
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: center, initialZoom: 14),
                  children: [
                    osmTileLayer(),
                    MarkerLayer(
                      markers: [
                        if (shop != null)
                          Marker(
                            point: shop,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.storefront_rounded,
                                size: 32, color: AppColors.brand),
                          ),
                        for (final s in list)
                          if (s.location != null)
                            Marker(
                              point: s.location!,
                              width: 120,
                              height: 56,
                              alignment: Alignment.topCenter,
                              child: _ShipperPin(status: s, stale: s.isLocationStale(now)),
                            ),
                      ],
                    ),
                    mapAttribution,
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('Chưa có shipper nào trong ca',
                            style: TextStyle(color: AppColors.muted)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: list.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return Text('${list.length} shipper trong ca',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted));
                          }
                          final s = list[i - 1];
                          return _ShipperTile(
                            status: s,
                            stale: s.isLocationStale(now),
                            onTap: s.location == null
                                ? null
                                : () => _map.move(s.location!, 16),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShipperPin extends StatelessWidget {
  final ShipperStatus status;
  final bool stale;

  const _ShipperPin({required this.status, required this.stale});

  @override
  Widget build(BuildContext context) {
    final color = stale ? AppColors.muted : AppColors.success;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(status.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        Icon(Icons.delivery_dining_rounded, size: 28, color: color),
      ],
    );
  }
}

class _ShipperTile extends StatelessWidget {
  final ShipperStatus status;
  final bool stale;
  final VoidCallback? onTap;

  const _ShipperTile({required this.status, required this.stale, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = status;
    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.delivery_dining_rounded,
              size: 32, color: stale ? AppColors.muted : AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Vào ca ${formatDateTime(s.shiftStartedAt).split(' ').last}'
                  ' · ${s.activeOrderIds.length} đơn đang giữ',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                Text(
                  s.location == null
                      ? 'Chưa có vị trí'
                      : 'GPS ${timeAgo(s.locationUpdatedAt)}'
                          '${stale ? ' – mất tín hiệu' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
                    color: stale ? AppColors.danger : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (s.phone.isNotEmpty)
            IconButton(
              tooltip: 'Sao chép SĐT ${s.phone}',
              icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.brand),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: s.phone));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Đã sao chép ${s.phone}')));
              },
            ),
        ],
      ),
    );
  }
}
