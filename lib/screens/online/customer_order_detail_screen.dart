import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/firestore_paths.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/customer_cart_provider.dart';
import '../../services/online_order_service.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/vietqr.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/reason_sheet.dart';
import 'my_orders_screen.dart' show StatusChip, statusColor;

/// Chi tiết đơn online của khách (bước 5): các bước trạng thái, mã VietQR +
/// đếm ngược, hủy khi quán chưa xác nhận (O15), đặt lại.
class CustomerOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const CustomerOrderDetailScreen({super.key, required this.orderId});

  @override
  State<CustomerOrderDetailScreen> createState() => _CustomerOrderDetailScreenState();
}

class _CustomerOrderDetailScreenState extends State<CustomerOrderDetailScreen> {
  // Broadcast vì có 2 nơi nghe: StreamBuilder và bộ theo dõi đổi trạng thái.
  late final Stream<Order?> _stream =
      OrderService.watchOrder(widget.orderId).asBroadcastStream();
  late final StreamSubscription<Order?> _paidWatcher;
  Timer? _ticker;
  bool _busy = false;
  OrderStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    // Tiền về (SePay) → đơn đổi từ "Chờ thanh toán" sang "Chờ xác nhận": báo khách.
    _paidWatcher = _stream.listen((o) {
      if (o == null) return;
      final prev = _lastStatus;
      _lastStatus = o.status;
      if (!mounted || prev == null || prev == o.status) return;
      if (prev == OrderStatus.awaitingPayment && o.status == OrderStatus.pending) {
        _toast('Thanh toán thành công – chờ quán xác nhận đơn');
      } else if (prev == OrderStatus.awaitingPayment && o.status == OrderStatus.cancelled) {
        _toast('Đơn đã hủy vì quá hạn thanh toán');
      }
    });
    // Cập nhật đồng hồ đếm ngược thanh toán.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _paidWatcher.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _cancel(Order order) async {
    final reason = await showReasonSheet(
      context,
      title: 'Lý do hủy đơn',
      reasons: customerCancelReasons,
      confirmLabel: 'Xác nhận hủy đơn',
      cancelLabel: 'Không hủy',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await OnlineOrderService.cancel(order.id, reason);
      _toast('Đã hủy đơn ${order.orderCode}');
    } on OnlineOrderError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Thêm lại các món của đơn vào giỏ theo giá hiện tại; báo món không còn bán.
  Future<void> _reorder(Order order) async {
    final cart = context.read<CustomerCartProvider>();
    setState(() => _busy = true);
    try {
      final ids = order.items.map((i) => i.productId).toSet().toList();
      final col = FirebaseFirestore.instance.collection(FsCollections.products);
      final docs = await Future.wait(ids.map((id) => col.doc(id).get()));
      final products = {
        for (final d in docs)
          if (d.exists) d.id: Product.fromDoc(d),
      };
      final skipped = <String>[];
      var added = 0;
      for (final item in order.items) {
        final p = products[item.productId];
        if (p == null || !p.isAvailable || !p.prices.containsKey(item.size)) {
          skipped.add(item.displayName);
          continue;
        }
        cart.add(p, size: item.size, quantity: item.quantity, note: item.note);
        added++;
      }
      if (!mounted) return;
      if (added == 0) {
        _toast('Các món trong đơn đều không còn bán');
        return;
      }
      _toast(skipped.isEmpty
          ? 'Đã thêm $added món vào giỏ'
          : 'Đã thêm $added món. Không còn bán: ${skipped.join(', ')}');
      Navigator.pushNamed(context, '/online_cart');
    } catch (e) {
      _toast(e is StateError ? e.message : 'Lỗi đặt lại: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Chi Tiết Đơn'),
      body: StreamBuilder<Order?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Lỗi tải đơn: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger)),
            );
          }
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final order = snap.data;
          if (order == null) return const Center(child: Text('Không tìm thấy đơn'));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              MeowCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MÃ ĐƠN',
                              style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          Text(order.orderCode,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.brand)),
                          Text('Đặt lúc ${formatDateTime(order.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    StatusChip(status: order.status),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (order.status == OrderStatus.awaitingPayment) ...[
                _VietQrPanel(order: order),
                const SizedBox(height: 12),
              ],
              if (order.status == OrderStatus.cancelled) ...[
                _CancelledBox(order: order),
                const SizedBox(height: 12),
              ],
              if (order.refund?.required == true) ...[
                RefundNotice(refund: order.refund!),
                const SizedBox(height: 12),
              ],
              _Timeline(order: order),
              const SizedBox(height: 12),
              _DeliveryCard(order: order),
              const SizedBox(height: 12),
              _ItemsCard(order: order),
              const SizedBox(height: 16),
              if (order.status.customerCanCancel)
                MeowSecondaryButton(
                  label: _busy ? 'Đang hủy…' : 'Hủy đơn',
                  icon: Icons.cancel_outlined,
                  textColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  borderColor: const Color(0xFFFECDD3),
                  onPressed: _busy ? null : () => _cancel(order),
                )
              else if (order.status.isActive)
                const Text(
                  'Quán đã xác nhận đơn. Muốn hủy hoặc đổi món, vui lòng nhắn Meow Shop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                )
              else
                MeowPrimaryButton(
                  label: 'Đặt lại',
                  icon: Icons.replay_rounded,
                  isLoading: _busy,
                  onPressed: _busy ? null : () => _reorder(order),
                ),
            ],
          );
        },
      ),
    );
  }
}

const _title = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Color(0xFF475569),
  letterSpacing: 0.5,
);

class _VietQrPanel extends StatelessWidget {
  final Order order;

  const _VietQrPanel({required this.order});

  @override
  Widget build(BuildContext context) {
    final expires = order.paymentExpiresAt;
    final left = expires?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    String mmss(Duration d) =>
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return MeowCard(
      padding: const EdgeInsets.all(16),
      borderColor: AppColors.warning,
      child: Column(
        children: [
          const Text('QUÉT MÃ ĐỂ THANH TOÁN', style: _title),
          const SizedBox(height: 4),
          Text(
            expired
                ? 'Đã hết hạn thanh toán – đơn sẽ tự hủy'
                : left == null
                    ? ''
                    : 'Còn ${mmss(left)} để chuyển khoản',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: expired ? AppColors.danger : AppColors.warning,
            ),
          ),
          if (!expired) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 220,
              height: 220,
              child: CachedNetworkImage(
                imageUrl: buildVietQrUrl(amount: order.total, content: order.transferContent),
                fit: BoxFit.contain,
                placeholder: (_, _) =>
                    const Center(child: CircularProgressIndicator(color: AppColors.brand)),
                errorWidget: (_, _, _) => const Center(
                  child: Text('Không tải được mã QR',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(formatMoney(order.total),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.brand)),
            SelectableText('Nội dung: ${order.transferContent}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Giữ nguyên số tiền và nội dung khi chuyển khoản. Đơn tự chuyển sang '
              '"Chờ xác nhận" khi quán nhận được tiền.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelledBox extends StatelessWidget {
  final Order order;

  const _CancelledBox({required this.order});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Đơn đã hủy lúc ${formatDateTime(order.cancelledAt)}'
          '${order.cancelReason != null ? '\nLý do: ${order.cancelReason}' : ''}',
          style: const TextStyle(color: AppColors.danger, height: 1.4),
        ),
      );
}

/// Thông tin hoàn tiền cho đơn đã trả trước (dùng cho cả khách và NV).
class RefundNotice extends StatelessWidget {
  final OrderRefund refund;

  const RefundNotice({super.key, required this.refund});

  @override
  Widget build(BuildContext context) {
    final done = refund.done;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        done
            ? 'Quán đã hoàn ${formatMoney(refund.amount)} lúc ${formatDateTime(refund.doneAt)}'
            : 'Quán sẽ hoàn ${formatMoney(refund.amount)} cho bạn. '
                'Quán sẽ liên hệ để xin số tài khoản nhận tiền.',
        style: TextStyle(
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: done ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}

/// Các bước của đơn online; bước hiện tại tô màu, bước đã qua có giờ.
class _Timeline extends StatelessWidget {
  final Order order;

  const _Timeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final steps = [
      if (order.paymentMethod == PaymentMethod.vietqr) OrderStatus.awaitingPayment,
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.delivering,
      OrderStatus.completed,
    ];
    final reachedIndex = steps.lastIndexWhere((s) => order.timeOf(s) != null);
    final currentIndex = steps.indexOf(order.status);

    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TIẾN TRÌNH', style: _title),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              label: steps[i].label,
              time: order.timeOf(steps[i]),
              done: i <= reachedIndex && !order.isCancelled,
              current: i == currentIndex,
              color: statusColor(steps[i]),
              isLast: i == steps.length - 1,
            ),
          if (order.status == OrderStatus.deliveryFailed)
            const Text('Giao không thành công – quán sẽ liên hệ bạn',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final DateTime? time;
  final bool done;
  final bool current;
  final Color color;
  final bool isLast;

  const _StepRow({
    required this.label,
    required this.time,
    required this.done,
    required this.current,
    required this.color,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final active = done || current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 20,
                color: active ? (current ? color : AppColors.success) : AppColors.borderSubtle,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? AppColors.success : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                          fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                          color: active ? AppColors.ink : AppColors.mutedLight,
                        )),
                  ),
                  if (time != null)
                    Text(formatDateTime(time).split(' ').last,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Order order;

  const _DeliveryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GIAO ĐẾN', style: _title),
          const SizedBox(height: 6),
          if (d != null) ...[
            Text('${d.receiverName} · ${d.receiverPhone}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(d.addressText, style: const TextStyle(color: AppColors.muted)),
            if (d.note.isNotEmpty)
              Text('Ghi chú: ${d.note}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            Text(
              'Quãng đường: ${d.distanceEstimated ? '~' : ''}'
              '${d.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            if (d.shipper != null)
              Text('Shipper: ${d.shipper!.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final Order order;

  const _ItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final fee = order.delivery?.fee ?? 0;
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MÓN', style: _title),
          const SizedBox(height: 8),
          for (final i in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i.displayName} × ${i.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (i.note.isNotEmpty)
                          Text(i.note,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(formatMoney(i.lineTotal)),
                ],
              ),
            ),
          if (order.note.isNotEmpty)
            Text('Ghi chú đơn: ${order.note}',
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
          for (final c in order.itemChanges)
            Text(
              'Quán đã bỏ ${c.displayName} × ${c.quantity} (−${formatMoney(c.amount)})'
              ' · ${c.reason}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          const Divider(),
          _row('Tạm tính', formatMoney(order.subtotal)),
          _row('Phí giao hàng', fee == 0 ? 'Miễn phí' : formatMoney(fee)),
          for (final f in order.extraFees) _row(f.label, formatMoney(f.amount)),
          _row('Tổng cộng', formatMoney(order.total), bold: true),
          if (order.delivery?.shipper != null &&
              (order.status == OrderStatus.ready || order.status == OrderStatus.delivering))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Shipper: ${order.delivery!.shipper!.name}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 4),
          Text(
            '${order.paymentMethod == PaymentMethod.cash ? 'Tiền mặt khi nhận hàng' : 'Chuyển khoản VietQR'}'
            ' · ${order.paymentStatus.label}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(l,
                    style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
            Text(v,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 17 : 14,
                    color: bold ? AppColors.brand : AppColors.ink)),
          ],
        ),
      );
}
