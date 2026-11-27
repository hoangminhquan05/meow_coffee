import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/shipper_status.dart';
import '../../providers/session_provider.dart';
import '../../services/online_order_service.dart';
import '../../services/shipper_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/meow_ui.dart';
import '../staff/online_orders_screen.dart' show timeAgo;
import 'held_orders.dart';
import 'shift_offer_stats.dart';

/// Màn chính của shipper: bắt đầu / kết thúc ca, gửi GPS mỗi 30 giây khi app
/// đang mở (O20), đơn đang giữ (bước 9). Lời mời giao đơn: ShipperShell.
class ShipperHomeScreen extends StatefulWidget {
  const ShipperHomeScreen({super.key});

  @override
  State<ShipperHomeScreen> createState() => _ShipperHomeScreenState();
}

class _ShipperHomeScreenState extends State<ShipperHomeScreen>
    with WidgetsBindingObserver {
  late final String _uid = context.read<SessionProvider>().uid;
  late final StreamSubscription<ShipperStatus> _sub;
  ShipperStatus? _status;
  Timer? _gpsTimer;
  Timer? _ticker;
  bool _busy = false;
  bool _sending = false;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = ShipperService.watchMine(_uid).listen(_onStatus, onError: (Object e) {
      debugPrint('ShipperHomeScreen status error: $e');
    });
    // Cập nhật "x phút trước".
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    _gpsTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mở lại app trong ca → gửi vị trí ngay.
    if (state == AppLifecycleState.resumed && (_status?.onShift ?? false)) _sendGps();
  }

  void _onStatus(ShipperStatus s) {
    final wasOn = _status?.onShift ?? false;
    setState(() => _status = s);
    if (s.onShift && _gpsTimer == null) {
      _gpsTimer = Timer.periodic(ShipperService.gpsInterval, (_) => _sendGps());
      if (!wasOn) _sendGps();
    } else if (!s.onShift) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
    }
  }

  Future<void> _sendGps() async {
    if (_sending) return;
    _sending = true;
    try {
      final pos = await getCurrentPosition();
      await ShipperService.sendLocation(_uid, LatLng(pos.latitude, pos.longitude));
      if (mounted && _gpsError != null) setState(() => _gpsError = null);
    } on LocationError catch (e) {
      if (mounted) setState(() => _gpsError = e.message);
    } catch (e) {
      debugPrint('sendGps error: $e');
      if (mounted) setState(() => _gpsError = 'Không gửi được vị trí, đang thử lại…');
    } finally {
      _sending = false;
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final pos = await getCurrentPosition();
      await ShipperService.startShift(LatLng(pos.latitude, pos.longitude));
      if (mounted) setState(() => _gpsError = null);
      _toast('Đã bắt đầu ca – giữ app mở để quán biết vị trí của bạn');
    } on LocationError catch (e) {
      _toast(e.message);
    } on OnlineOrderError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final ok = await showMeowConfirmDialog(
      context,
      title: 'Kết thúc ca',
      message: 'Bạn sẽ không nhận được đơn mới cho đến khi bắt đầu ca lại.',
      confirmLabel: 'Kết thúc ca',
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ShipperService.endShift();
      _toast('Đã kết thúc ca');
    } on OnlineOrderError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Giao Hàng'),
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _ShiftCard(status: s),
                const SizedBox(height: 12),
                if (s.onShift) ...[
                  if (_gpsError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_off_rounded, color: AppColors.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_gpsError\nMất vị trí quá 15 phút sẽ tự kết thúc ca.',
                              style: const TextStyle(color: AppColors.danger, height: 1.35),
                            ),
                          ),
                          TextButton(onPressed: _sendGps, child: const Text('Thử lại')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (s.location != null) ...[
                    MapPreview(location: s.location!, height: 180),
                    const SizedBox(height: 6),
                    Text(
                      'Vị trí gửi lúc ${timeAgo(s.locationUpdatedAt)} · tự cập nhật mỗi 30 giây khi app mở',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Lời mời trong ca: luôn hiện để shipper nắm tình trạng (O35).
                  ShiftOfferStats(uid: _uid, shiftId: s.shiftId, compact: true),
                  const SizedBox(height: 12),
                  if (s.codHolding > 0) ...[
                    MeowCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.warning),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('Tiền COD đang giữ')),
                          Text(formatMoney(s.codHolding),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  HeldOrders(orderIds: s.activeOrderIds),
                  const SizedBox(height: 16),
                  MeowSecondaryButton(
                    label: 'Kết thúc ca',
                    icon: Icons.logout_rounded,
                    textColor: AppColors.danger,
                    backgroundColor: AppColors.dangerSoft,
                    borderColor: const Color(0xFFFECDD3),
                    onPressed: _busy ? null : _end,
                  ),
                ] else ...[
                  const Text(
                    'Bắt đầu ca để nhận đơn giao. App cần quyền vị trí và phải đang mở '
                    'để gửi vị trí cho quán.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  MeowPrimaryButton(
                    label: 'Bắt đầu ca',
                    icon: Icons.play_arrow_rounded,
                    isLoading: _busy,
                    onPressed: _busy ? null : _start,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final ShipperStatus status;

  const _ShiftCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final on = status.onShift;
    final started = status.shiftStartedAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: on ? AppColors.brandGradient : null,
        color: on ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: on ? null : Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(on ? Icons.delivery_dining_rounded : Icons.bedtime_outlined,
              size: 40, color: on ? Colors.white : AppColors.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(on ? 'Đang trong ca' : 'Đang nghỉ',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: on ? Colors.white : AppColors.ink)),
                if (on && started != null)
                  Text('Bắt đầu lúc ${formatDateTime(started).split(' ').last}',
                      style: const TextStyle(color: Color(0xFFEEE6FF))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
