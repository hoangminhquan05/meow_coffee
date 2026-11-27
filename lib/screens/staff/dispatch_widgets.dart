import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../models/shipper_status.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/shipper_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Một dòng tình trạng giao hàng của đơn online (bước 9):
/// đang mời ai · chưa có shipper · ai đang giữ / đang giao · lần giao thất bại.
class DispatchInfo extends StatefulWidget {
  final Order order;
  final bool detailed;

  const DispatchInfo({super.key, required this.order, this.detailed = false});

  @override
  State<DispatchInfo> createState() => _DispatchInfoState();
}

class _DispatchInfoState extends State<DispatchInfo> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant DispatchInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// Đếm ngược lời mời mỗi giây khi đang mời.
  void _syncTicker() {
    final offering = widget.order.status == OrderStatus.ready &&
        widget.order.dispatch?.state == DispatchState.offering;
    if (offering && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!offering) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final d = o.delivery;
    final shipper = d?.shipper;
    final (IconData icon, Color color, String text) = switch (o.status) {
      OrderStatus.ready when shipper != null => (
          Icons.delivery_dining_rounded,
          AppColors.success,
          '${shipper.name} đã nhận – chờ lấy hàng'
              '${o.dispatch?.manualBy != null ? ' (gán bởi ${o.dispatch!.manualBy!.name})' : ''}',
        ),
      OrderStatus.ready => switch (o.dispatch?.state) {
          DispatchState.offering => (
              Icons.hourglass_top_rounded,
              AppColors.warning,
              'Đang mời ${o.dispatch!.offeredTo?.name ?? 'shipper'}'
                  ' · còn ${_secondsLeft(o.dispatch!.expiresAt)}s',
            ),
          DispatchState.noShipper => (
              Icons.person_off_outlined,
              AppColors.danger,
              'Chưa có shipper nhận'
                  '${(o.dispatch?.declinedBy.length ?? 0) > 0 ? ' (${o.dispatch!.declinedBy.length} người từ chối/bỏ lỡ)' : ''}'
                  ' – Mời lại hoặc gán shipper',
            ),
          _ => (Icons.search_rounded, AppColors.warning, 'Đang tìm shipper…'),
        },
      OrderStatus.delivering => (
          Icons.two_wheeler_rounded,
          AppColors.brand,
          '${shipper?.name ?? 'Shipper'} đang giao'
              '${d?.arrivedAt != null ? ' · đến nơi ${formatDateTime(d!.arrivedAt).split(' ').last}' : ''}'
              '${(d?.callAttempts.length ?? 0) > 0 ? ' · đã gọi ${d!.callAttempts.length} lần' : ''}',
        ),
      OrderStatus.deliveryFailed => (
          Icons.report_gmailerrorred_rounded,
          AppColors.danger,
          o.failedAttempts.isEmpty
              ? 'Giao không thành công'
              : 'Giao không thành công: ${o.failedAttempts.last.reason}'
                  ' (${o.failedAttempts.last.by.name}, gọi ${o.failedAttempts.last.callAttempts} lần)',
        ),
      OrderStatus.completed when shipper != null => (
          Icons.check_circle_outline_rounded,
          AppColors.success,
          'Đã giao bởi ${shipper.name}'
              '${d?.deliveredAt != null ? ' lúc ${formatDateTime(d!.deliveredAt)}' : ''}'
              '${o.codAmount > 0 ? ' · thu ${formatMoney(o.codAmount)}' : ''}',
        ),
      _ => (Icons.info_outline, AppColors.muted, ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, height: 1.35, color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  static int _secondsLeft(DateTime? exp) =>
      exp == null ? 0 : exp.difference(DateTime.now()).inSeconds.clamp(0, 999);
}

/// Chọn shipper đang trong ca để gán đơn.
class PickShipperSheet extends StatelessWidget {
  final String? currentId;

  const PickShipperSheet({super.key, this.currentId});

  @override
  Widget build(BuildContext context) {
    final max = context.read<ShopSettingsProvider>().settings.dispatch.maxOrdersPerShipper;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Chọn shipper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Text('Đơn giao thẳng cho shipper này, không cần họ bấm Nhận.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 8),
              Flexible(
                child: StreamBuilder<List<ShipperStatus>>(
                  stream: ShipperService.watchOnShift(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
                      );
                    }
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Không có shipper nào trong ca', textAlign: TextAlign.center),
                      );
                    }
                    final now = DateTime.now();
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: AppColors.soft,
                              child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                  style: const TextStyle(color: AppColors.brand)),
                            ),
                            title: Text(s.name),
                            subtitle: Text(
                              'Đang giữ ${s.activeOrderIds.length}/$max đơn · '
                              '${s.isLocationStale(now) ? 'mất GPS' : 'có GPS'}'
                              '${s.liveOffer(now) != null ? ' · đang có lời mời' : ''}',
                            ),
                            trailing: s.uid == currentId
                                ? const Text('Đang giữ', style: TextStyle(color: AppColors.muted))
                                : const Icon(Icons.chevron_right_rounded),
                            enabled: s.uid != currentId,
                            onTap: () => Navigator.pop(context, s),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
