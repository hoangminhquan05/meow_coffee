import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../models/shipper_status.dart';
import '../../services/online_order_service.dart';
import '../../services/shipper_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/alert_sound.dart';
import '../../utils/formatters.dart';

/// Lời mời giao đơn toàn màn hình: đếm ngược, chuông + rung, Nhận / Từ chối.
/// Hết giờ → báo Worker "hết giờ" (tính như từ chối – O35).
/// Trả về true nếu shipper đã nhận đơn.
Future<bool> showOfferDialog(BuildContext context, PendingOffer offer) async {
  final accepted = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    pageBuilder: (_, _, _) => _OfferDialog(offer: offer),
  );
  return accepted ?? false;
}

class _OfferDialog extends StatefulWidget {
  final PendingOffer offer;

  const _OfferDialog({required this.offer});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  late final StreamSubscription<Order?> _sub;
  Timer? _ticker;
  Order? _order;
  bool _busy = false;
  bool _closed = false;
  int _total = 60;

  PendingOffer get offer => widget.offer;

  int get _secondsLeft {
    final exp = offer.expiresAt;
    if (exp == null) return 0;
    return exp.difference(DateTime.now()).inSeconds.clamp(0, 999);
  }

  @override
  void initState() {
    super.initState();
    _total = _secondsLeft.clamp(1, 999);
    AlertSound.ringLoop();
    HapticFeedback.vibrate();
    _sub = ShipperOrderService.watchOrder(offer.orderId).listen((o) {
      if (!mounted) return;
      // Đơn đã đổi người / bị hủy / quán gán tay → đóng lời mời.
      if (o == null || o.status != OrderStatus.ready || o.dispatch?.offerId != offer.offerId) {
        _close(false, message: 'Lời mời đã được chuyển hoặc đơn đã thay đổi');
        return;
      }
      setState(() => _order = o);
    }, onError: (Object e) {
      // Không còn quyền đọc đơn (đã chuyển cho người khác).
      _close(false, message: 'Lời mời không còn hiệu lực');
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _secondsLeft;
      if (left % 5 == 0) HapticFeedback.vibrate();
      if (left <= 0) {
        _respond('timeout');
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub.cancel();
    AlertSound.stop();
    super.dispose();
  }

  void _close(bool accepted, {String? message}) {
    if (_closed || !mounted) return;
    _closed = true;
    _ticker?.cancel();
    AlertSound.stop();
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop(accepted);
    if (message != null) messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _respond(String action) async {
    if (_busy || _closed) return;
    setState(() => _busy = true);
    AlertSound.stop();
    _ticker?.cancel();
    try {
      final warning = await ShipperOrderService.respond(
        orderId: offer.orderId,
        offerId: offer.offerId,
        action: action,
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      _closed = true;
      nav.pop(action == 'accept');
      if (warning != null && nav.mounted) {
        await showDialog<void>(
          context: nav.context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 36),
            title: const Text('Lưu ý'),
            content: Text(warning),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
            ],
          ),
        );
      }
    } on OnlineOrderError catch (e) {
      _close(false, message: e.message);
    } catch (e) {
      _close(false, message: 'Lỗi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final left = _secondsLeft;
    final collect = o?.amountToCollect ?? 0;
    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: AppColors.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('ĐƠN MỚI CẦN GIAO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.brand)),
                const SizedBox(height: 4),
                Text(offer.orderCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: left / _total,
                          strokeWidth: 10,
                          backgroundColor: AppColors.soft,
                          color: left <= 10 ? AppColors.danger : AppColors.brand,
                        ),
                        Center(
                          child: Text('$left',
                              style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: left <= 10 ? AppColors.danger : AppColors.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: o == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                      : ListView(
                          children: [
                            _row(Icons.place_outlined, o.delivery?.addressText ?? ''),
                            _row(Icons.route_outlined,
                                '${(o.delivery?.distanceKm ?? 0).toStringAsFixed(1)} km từ quán'),
                            _row(
                              Icons.payments_outlined,
                              collect > 0
                                  ? 'Thu của khách: ${formatMoney(collect)}'
                                      '${o.paymentMethod == PaymentMethod.cash ? ' (COD)' : ' (phí giao lại)'}'
                                  : 'Đã thanh toán trước – không thu tiền',
                              bold: true,
                              color: collect > 0 ? AppColors.warning : AppColors.success,
                            ),
                            _row(Icons.receipt_long_outlined, 'Tổng đơn: ${formatMoney(o.total)}'),
                            const Divider(height: 24),
                            Text('${o.totalItems} món',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            for (final i in o.items)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('${i.quantity} × ${i.displayName}'),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _busy ? null : () => _respond('decline'),
                        child: const Text('Từ chối',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: AppColors.success,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _busy || o == null ? null : () => _respond('accept'),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Nhận đơn',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: color ?? AppColors.ink,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            ),
          ],
        ),
      );
}
