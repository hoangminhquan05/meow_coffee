import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/order_receipt.dart';
import '../payment/payment_screen.dart' show exportInvoicePdf;

/// Chi tiết đơn (L9): xem, in lại PDF, hủy đơn theo quyền (Q7).
class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final Stream<Order?> _stream = OrderService.watchOrder(widget.orderId);
  Timer? _ticker;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // Cập nhật đồng hồ "còn X phút để hủy".
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _cancel(Order order) async {
    final session = context.read<SessionProvider>();
    final user = session.user;
    if (user == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelReasonDialog(),
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    try {
      // Kiểm tra lại quyền ngay lúc hủy (có thể đã quá 30 phút).
      await OrderService.cancelOrder(order: order, by: user, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã hủy đơn ${order.orderCode}')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không hủy được đơn: $msg')),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Chi Tiết Đơn'),
      body: StreamBuilder<Order?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Lỗi tải đơn: ${snapshot.error}',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            );
          }
          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('Không tìm thấy đơn'));
          }
          final canCancel = OrderService.canCancel(order, session.user);
          final remaining = OrderService.staffCancelRemaining(order);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              MeowCard(
                padding: const EdgeInsets.all(20),
                child: OrderReceiptView(order: order),
              ),
              const SizedBox(height: 16),
              MeowPrimaryButton(
                label: 'In lại hóa đơn PDF',
                icon: Icons.picture_as_pdf_outlined,
                height: 48,
                onPressed: () => exportInvoicePdf(context, order),
              ),
              if (!order.isCancelled) ...[
                const SizedBox(height: 10),
                if (canCancel) ...[
                  MeowSecondaryButton(
                    label: _cancelling ? 'Đang hủy...' : 'Hủy đơn',
                    icon: Icons.cancel_outlined,
                    height: 46,
                    textColor: AppColors.danger,
                    backgroundColor: AppColors.dangerSoft,
                    borderColor: const Color(0xFFFECDD3),
                    onPressed: _cancelling ? null : () => _cancel(order),
                  ),
                  if (!session.isAdmin && remaining != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Còn ${remaining.inMinutes + 1} phút để hủy',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                ] else
                  const Text(
                    'Liên hệ quản lý để hủy đơn này',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Lý do hủy bắt buộc, nhập tự do (Q7).
class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.trim().isEmpty;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hủy đơn',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Đơn sẽ chuyển sang "Đã hủy" và không tính vào doanh thu. '
              'Nhớ trả lại tiền cho khách.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Lý do hủy *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            MeowPrimaryButton(
              label: 'Xác nhận hủy đơn',
              height: 48,
              solidColor: AppColors.danger,
              onPressed: empty
                  ? null
                  : () => Navigator.pop(context, _controller.text.trim()),
            ),
            const SizedBox(height: 10),
            MeowSecondaryButton(
              label: 'Không hủy',
              height: 46,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
