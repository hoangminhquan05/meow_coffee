import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/online_order_service.dart';
import '../../services/shipper_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/launchers.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/reason_sheet.dart';

/// Chi tiết đơn shipper đang giữ: Gọi, Chỉ đường, Đã lấy hàng, Đã đến nơi,
/// Đã giao (xác nhận đã thu tiền), Giao không thành công (O29).
class ShipperOrderScreen extends StatefulWidget {
  final String orderId;

  const ShipperOrderScreen({super.key, required this.orderId});

  @override
  State<ShipperOrderScreen> createState() => _ShipperOrderScreenState();
}

class _ShipperOrderScreenState extends State<ShipperOrderScreen> {
  late final Stream<Order?> _stream = ShipperOrderService.watchOrder(widget.orderId);
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Đếm lùi thời gian chờ trước khi được báo giao thất bại.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) _toast(done);
    } on OnlineOrderError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(Order o) async {
    final phone = o.delivery?.receiverPhone ?? '';
    if (phone.isEmpty) return _toast('Đơn không có số điện thoại');
    final opened = await openDialer(phone);
    if (!opened) _toast('Không mở được trình gọi điện');
    // Ghi số lần gọi (điều kiện báo giao thất bại).
    try {
      await ShipperOrderService.called(o.id);
    } on OnlineOrderError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delivered(Order o) async {
    final collect = o.amountToCollect;
    final ok = await showMeowConfirmDialog(
      context,
      title: collect > 0 ? 'Đã thu ${formatMoney(collect)}?' : 'Xác nhận đã giao',
      message: collect > 0
          ? 'Xác nhận bạn đã nhận đủ ${formatMoney(collect)} tiền mặt của khách. '
              'Số tiền này được cộng vào tiền COD bạn đang giữ.'
          : 'Đơn đã thanh toán trước, không thu thêm tiền.',
      confirmLabel: collect > 0 ? 'Đã thu ${formatMoney(collect)}' : 'Đã giao',
      isDanger: false,
      icon: Icons.check_circle_outline_rounded,
    );
    if (!ok || !mounted) return;
    await _run(() => ShipperOrderService.delivered(o.id, collected: collect > 0),
        done: 'Đã giao xong ${o.orderCode}');
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _failed(Order o) async {
    final reason = await showReasonSheet(
      context,
      title: 'Giao không thành công',
      reasons: ShipperOrderService.failReasons,
      confirmLabel: 'Báo giao thất bại',
      message: 'Mang đơn về quán. Quán sẽ quyết định giao lại hoặc hủy đơn.',
    );
    if (reason == null || !mounted) return;
    await _run(() => ShipperOrderService.failed(o.id, reason), done: 'Đã báo giao thất bại');
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<SessionProvider>().uid;
    final fail = context.watch<ShopSettingsProvider>().settings.deliveryFailure;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Đơn giao'), backgroundColor: AppColors.bg),
      body: StreamBuilder<Order?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Đơn này không còn do bạn giao'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final o = snap.data;
          if (o == null) return const Center(child: Text('Không tìm thấy đơn'));
          final mine = o.delivery?.shipper?.id == uid;
          final d = o.delivery;
          final collect = o.amountToCollect;
          final now = DateTime.now();
          final calls = d?.callAttempts.length ?? 0;
          final waitLeft = ShipperOrderService.minutesLeft(d?.arrivedAt, fail.waitMinutes, now);
          final canFail = d?.arrivedAt != null && waitLeft == 0 && calls >= fail.minCallAttempts;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(o.orderCode,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  Chip(
                    label: Text(o.status.label),
                    backgroundColor: AppColors.soft,
                    side: BorderSide.none,
                  ),
                ],
              ),
              if (!mine)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Đơn này đã được quán chuyển cho shipper khác.'),
                ),
              const SizedBox(height: 12),
              MeowCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d?.receiverName ?? '',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(d?.receiverPhone ?? '', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 8),
                    Text(d?.addressText ?? '', style: const TextStyle(height: 1.35)),
                    if ((d?.note ?? '').isNotEmpty)
                      Text('Ghi chú địa chỉ: ${d!.note}',
                          style: const TextStyle(color: AppColors.muted, height: 1.35)),
                    if (o.note.isNotEmpty)
                      Text('Ghi chú đơn: ${o.note}',
                          style: const TextStyle(color: AppColors.muted, height: 1.35)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: mine &&
                                    (o.status == OrderStatus.delivering ||
                                        o.status == OrderStatus.ready)
                                ? () => _call(o)
                                : null,
                            icon: const Icon(Icons.call_rounded),
                            label: Text(calls > 0 ? 'Gọi ($calls)' : 'Gọi'),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: d?.location == null ? null : () => openDirections(d!.location!),
                            icon: const Icon(Icons.directions_rounded),
                            label: const Text('Chỉ đường'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (d?.location != null) ...[
                const SizedBox(height: 12),
                MapPreview(location: d!.location!, height: 160),
              ],
              const SizedBox(height: 12),
              MeowCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final i in o.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${i.quantity} × ${i.displayName}'
                            '${i.note.isNotEmpty ? ' – ${i.note}' : ''}'),
                      ),
                    const Divider(height: 20),
                    for (final f in o.extraFees)
                      Text('${f.label}: ${formatMoney(f.amount)}'),
                    Text('Tổng đơn: ${formatMoney(o.total)}'),
                    const SizedBox(height: 4),
                    Text(
                      collect > 0
                          ? 'THU CỦA KHÁCH: ${formatMoney(collect)}'
                          : 'Đã thanh toán trước – không thu tiền',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: collect > 0 ? AppColors.warning : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (mine && o.status == OrderStatus.ready)
                MeowPrimaryButton(
                  label: 'Đã lấy hàng',
                  icon: Icons.inventory_2_outlined,
                  isLoading: _busy,
                  onPressed: _busy
                      ? null
                      : () => _run(() => ShipperOrderService.pickedUp(o.id), done: 'Bắt đầu giao'),
                ),
              if (mine && o.status == OrderStatus.delivering) ...[
                if (d?.arrivedAt == null)
                  MeowSecondaryButton(
                    label: 'Đã đến nơi',
                    icon: Icons.flag_outlined,
                    onPressed: _busy ? null : () => _run(() => ShipperOrderService.arrived(o.id)),
                  )
                else
                  Text('Đến nơi lúc ${formatDateTime(d!.arrivedAt).split(' ').last}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 10),
                MeowPrimaryButton(
                  label: collect > 0 ? 'Đã giao · thu ${formatMoney(collect)}' : 'Đã giao',
                  icon: Icons.check_circle_rounded,
                  isLoading: _busy,
                  onPressed: _busy ? null : () => _delivered(o),
                ),
                const SizedBox(height: 10),
                MeowSecondaryButton(
                  label: 'Giao không thành công',
                  icon: Icons.report_gmailerrorred_rounded,
                  textColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  borderColor: const Color(0xFFFECDD3),
                  onPressed: canFail && !_busy ? () => _failed(o) : null,
                ),
                if (!canFail)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      d?.arrivedAt == null
                          ? 'Bấm "Đã đến nơi" khi tới địa chỉ khách.'
                          : 'Báo giao thất bại được sau khi ${[
                              if (waitLeft > 0) 'chờ thêm $waitLeft phút',
                              if (calls < fail.minCallAttempts)
                                'gọi khách thêm ${fail.minCallAttempts - calls} lần',
                            ].join(' và ')}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
