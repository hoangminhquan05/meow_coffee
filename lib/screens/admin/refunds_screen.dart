import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../services/staff_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

/// Admin: đơn đã trả trước cần hoàn tiền tay (O32). Chuyển khoản cho khách
/// xong thì bấm "Đã hoàn" kèm ghi chú.
class RefundsScreen extends StatefulWidget {
  const RefundsScreen({super.key});

  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends State<RefundsScreen> {
  late Stream<List<Order>> _stream = StaffOrderService.watchPendingRefunds();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Cần Hoàn Tiền'),
      body: StreamBuilder<List<Order>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Lỗi tải danh sách: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    MeowSecondaryButton(
                      label: 'Thử lại',
                      onPressed: () => setState(
                          () => _stream = StaffOrderService.watchPendingRefunds()),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final orders = snap.data!;
          if (orders.isEmpty) {
            return const Center(
              child: Text('Không có đơn nào cần hoàn tiền',
                  style: TextStyle(color: AppColors.muted)),
            );
          }
          final total = orders.fold<int>(0, (s, o) => s + o.refund!.amount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('${orders.length} đơn · tổng ${formatMoney(total)}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
              const SizedBox(height: 8),
              for (final o in orders) ...[
                _RefundTile(order: o),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RefundTile extends StatefulWidget {
  final Order order;

  const _RefundTile({required this.order});

  @override
  State<_RefundTile> createState() => _RefundTileState();
}

class _RefundTileState extends State<_RefundTile> {
  bool _busy = false;

  Future<void> _markDone() async {
    final order = widget.order;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Đã hoàn ${formatMoney(order.refund!.amount)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Đơn ${order.orderCode} · ${order.customer?.name ?? ''}'),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (ngân hàng, mã giao dịch…)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đã hoàn')),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await StaffOrderService.markRefunded(
        orderId: order.id,
        note: text,
        by: context.read<SessionProvider>().personRef,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã ghi nhận hoàn tiền ${order.orderCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is StateError ? e.message : 'Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final phone = o.customer?.phone ?? '';
    final reason = o.isCancelled
        ? 'Hủy đơn: ${o.cancelReason ?? ''}'
        : 'Quán bỏ món: ${o.itemChanges.map((c) => '${c.displayName} ×${c.quantity}').join(', ')}';
    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.pushNamed(context, '/online_order', arguments: o.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.orderCode,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Text(formatMoney(o.refund!.amount),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('${o.customer?.name ?? ''} · $phone',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (phone.isNotEmpty)
                IconButton(
                  tooltip: 'Sao chép SĐT',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.brand),
                  onPressed: () => Clipboard.setData(ClipboardData(text: phone)),
                ),
            ],
          ),
          Text(reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          Text(
            '${o.paymentMethod == PaymentMethod.vietqr ? 'Đã trả VietQR' : 'Đã trả'} '
            '· ${formatDateTime(o.cancelledAt ?? o.createdAt)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          MeowPrimaryButton(
            label: 'Đã hoàn tiền',
            height: 44,
            isLoading: _busy,
            onPressed: _busy ? null : _markDone,
          ),
        ],
      ),
    );
  }
}
