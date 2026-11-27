import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/staff_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';
import '../online/customer_order_detail_screen.dart' show RefundNotice;
import '../online/my_orders_screen.dart' show StatusChip;
import 'dispatch_widgets.dart';
import 'online_order_actions.dart';

/// Chi tiết đơn online cho NV/admin: khách, địa chỉ, món (bỏ món), tiền,
/// lịch sử trạng thái, nút bước tiếp theo / từ chối / hủy.
class OnlineOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OnlineOrderDetailScreen({super.key, required this.orderId});

  @override
  State<OnlineOrderDetailScreen> createState() => _OnlineOrderDetailScreenState();
}

class _OnlineOrderDetailScreenState extends State<OnlineOrderDetailScreen> {
  late final Stream<Order?> _stream = OrderService.watchOrder(widget.orderId);
  bool _busy = false;

  Future<void> _run(Future<Object?> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Đơn Online'),
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

          final next = nextStepLabel(order.status);
          final canCancel = StaffOrderService.shopCancellable.contains(order.status);
          final canEdit = StaffOrderService.itemEditable.contains(order.status);

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
              if (order.isCancelled) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Đã hủy lúc ${formatDateTime(order.cancelledAt)}'
                    '${order.cancelledBy != null ? ' bởi ${order.cancelledBy!.name}' : ''}'
                    '${order.cancelReason != null ? '\nLý do: ${order.cancelReason}' : ''}',
                    style: const TextStyle(color: AppColors.danger, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (order.refund?.required == true) ...[
                RefundNotice(refund: order.refund!),
                const SizedBox(height: 12),
              ],
              _CustomerCard(order: order),
              const SizedBox(height: 12),
              if (order.dispatch != null || order.delivery?.shipper != null) ...[
                MeowCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('GIAO HÀNG', style: _title),
                      const SizedBox(height: 8),
                      DispatchInfo(order: order, detailed: true),
                      if ((order.delivery?.shipperPhone ?? '').isNotEmpty &&
                          order.status != OrderStatus.completed)
                        _PhoneLine(
                            name: 'Shipper ${order.delivery!.shipper?.name ?? ''}',
                            phone: order.delivery!.shipperPhone!),
                      for (final f in order.failedAttempts)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '• ${formatDateTime(f.at)} – ${f.by.name}: ${f.reason}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _ItemsCard(
                order: order,
                canEdit: canEdit && !_busy,
                onRemove: (i) =>
                    _run(() => OnlineOrderActions.removeItem(context, order, i)),
              ),
              const SizedBox(height: 12),
              _HistoryCard(order: order),
              const SizedBox(height: 16),
              if (next != null) ...[
                MeowPrimaryButton(
                  label: next,
                  isLoading: _busy,
                  onPressed: _busy
                      ? null
                      : () => _run(() => OnlineOrderActions.advance(context, order)),
                ),
                const SizedBox(height: 10),
              ],
              if (order.status == OrderStatus.ready) ...[
                Row(
                  children: [
                    if (order.delivery?.shipper == null &&
                        order.dispatch?.state != DispatchState.offering) ...[
                      Expanded(
                        child: MeowSecondaryButton(
                          label: 'Mời lại',
                          icon: Icons.refresh_rounded,
                          onPressed: _busy
                              ? null
                              : () => _run(() => OnlineOrderActions.retry(context, order)),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: MeowSecondaryButton(
                        label: order.delivery?.shipper == null ? 'Gán shipper' : 'Đổi shipper',
                        icon: Icons.swap_horiz_rounded,
                        onPressed: _busy
                            ? null
                            : () => _run(() => OnlineOrderActions.assign(context, order)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (order.status == OrderStatus.deliveryFailed) ...[
                MeowPrimaryButton(
                  label: 'Giao lại',
                  icon: Icons.replay_rounded,
                  isLoading: _busy,
                  onPressed: _busy
                      ? null
                      : () => _run(() => OnlineOrderActions.redeliver(context, order)),
                ),
                const SizedBox(height: 10),
                MeowSecondaryButton(
                  label: 'Hủy đơn (không hoàn tiền)',
                  icon: Icons.cancel_outlined,
                  textColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  borderColor: const Color(0xFFFECDD3),
                  onPressed: _busy
                      ? null
                      : () => _run(() => OnlineOrderActions.cancelFailed(context, order)),
                ),
              ],
              if (canCancel)
                MeowSecondaryButton(
                  label: order.status == OrderStatus.pending ? 'Từ chối đơn' : 'Hủy đơn',
                  icon: Icons.cancel_outlined,
                  textColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  borderColor: const Color(0xFFFECDD3),
                  onPressed: _busy
                      ? null
                      : () => _run(() => OnlineOrderActions.cancel(context, order)),
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

class _CustomerCard extends StatelessWidget {
  final Order order;

  const _CustomerCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    final c = order.customer;
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('KHÁCH HÀNG', style: _title),
          const SizedBox(height: 6),
          if (c != null) _PhoneLine(name: c.name, phone: c.phone),
          if (d != null) ...[
            const SizedBox(height: 10),
            const Text('GIAO ĐẾN', style: _title),
            const SizedBox(height: 6),
            _PhoneLine(name: d.receiverName, phone: d.receiverPhone),
            Text(d.addressText, style: const TextStyle(color: AppColors.inkSlate)),
            if (d.note.isNotEmpty)
              Text('Ghi chú cho shipper: ${d.note}',
                  style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
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

/// Tên + SĐT, bấm biểu tượng để sao chép SĐT.
class _PhoneLine extends StatelessWidget {
  final String name;
  final String phone;

  const _PhoneLine({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('$name · $phone',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (phone.isNotEmpty)
          IconButton(
            tooltip: 'Sao chép SĐT',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.brand),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Đã sao chép $phone')));
            },
          ),
      ],
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final Order order;
  final bool canEdit;
  final void Function(int index) onRemove;

  const _ItemsCard({required this.order, required this.canEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('MÓN', style: _title)),
              if (canEdit)
                const Text('Bấm − để bỏ món',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < order.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${order.items[i].displayName} × ${order.items[i].quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        if (order.items[i].note.isNotEmpty)
                          Text(order.items[i].note,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(formatMoney(order.items[i].lineTotal)),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Bỏ món',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline,
                          color: AppColors.danger, size: 20),
                      onPressed: () => onRemove(i),
                    ),
                ],
              ),
            ),
          for (final c in order.itemChanges)
            Text(
              'Đã bỏ ${c.displayName} × ${c.quantity} (−${formatMoney(c.amount)}) · '
              '${c.reason} · ${c.by.name} ${formatDateTime(c.at)}',
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          if (order.note.isNotEmpty)
            Text('Ghi chú đơn: ${order.note}',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          const Divider(),
          _row('Tạm tính', formatMoney(order.subtotal)),
          _row('Phí giao hàng',
              order.deliveryFee == 0 ? 'Miễn phí' : formatMoney(order.deliveryFee)),
          for (final f in order.extraFees) _row(f.label, formatMoney(f.amount)),
          _row('Tổng cộng', formatMoney(order.total), bold: true),
          const SizedBox(height: 4),
          Text(
            '${order.paymentMethod == PaymentMethod.cash ? 'COD – thu tiền khi giao' : 'Chuyển khoản VietQR'}'
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

/// Lịch sử trạng thái kèm người thao tác (nội bộ).
class _HistoryCard extends StatelessWidget {
  final Order order;

  const _HistoryCard({required this.order});

  static String _who(StatusEntry e) => e.byRole == 'customer'
      ? 'Khách'
      : (e.byName.isEmpty ? e.byRole : e.byName);

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LỊCH SỬ', style: _title),
          const SizedBox(height: 8),
          for (final e in order.statusHistory)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(formatDateTime(e.at),
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                  Expanded(
                    child: Text('${e.status.label} · ${_who(e)}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
