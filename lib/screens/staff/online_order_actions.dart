import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../services/staff_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/reason_sheet.dart';

/// Nhãn nút bước kế tiếp theo trạng thái hiện tại.
String? nextStepLabel(OrderStatus s) => switch (s) {
      OrderStatus.pending => 'Xác nhận',
      OrderStatus.confirmed => 'Bắt đầu pha',
      OrderStatus.preparing => 'Pha xong',
      _ => null,
    };

/// Thao tác NV/admin dùng chung cho màn danh sách và chi tiết đơn online.
class OnlineOrderActions {
  OnlineOrderActions._();

  static (PersonRef, String) _actor(BuildContext context) {
    final session = context.read<SessionProvider>();
    return (session.personRef, session.user?.role.value ?? 'staff');
  }

  static void _toast(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  static String _error(Object e) =>
      e is StateError ? e.message : 'Lỗi: $e';

  /// Chuyển bước kế tiếp. Trả về true nếu thành công.
  static Future<bool> advance(BuildContext context, Order order) async {
    final (by, role) = _actor(context);
    final to = StaffOrderService.nextStep[order.status];
    try {
      await StaffOrderService.advance(
          orderId: order.id, from: order.status, by: by, role: role);
      if (context.mounted && to != null) {
        _toast(context, '${order.orderCode}: ${to.label}');
      }
      return true;
    } catch (e) {
      if (context.mounted) _toast(context, _error(e));
      return false;
    }
  }

  /// Từ chối (Chờ xác nhận) hoặc hủy đơn (trước khi shipper lấy hàng).
  static Future<bool> cancel(BuildContext context, Order order) async {
    final reject = order.status == OrderStatus.pending;
    final paid = order.paymentStatus == PaymentStatus.paid;
    final reason = await showReasonSheet(
      context,
      title: reject ? 'Từ chối đơn ${order.orderCode}' : 'Hủy đơn ${order.orderCode}',
      message: paid
          ? 'Khách đã chuyển khoản ${formatMoney(order.total)} – đơn sẽ vào danh sách '
              '"Cần hoàn tiền" để admin hoàn tay.'
          : null,
      reasons: StaffOrderService.rejectReasons,
      confirmLabel: reject ? 'Từ chối đơn' : 'Hủy đơn',
    );
    if (reason == null || !context.mounted) return false;
    final (by, role) = _actor(context);
    try {
      await StaffOrderService.cancelByShop(
          orderId: order.id, reason: reason, by: by, role: role);
      if (context.mounted) {
        _toast(context, reject ? 'Đã từ chối ${order.orderCode}' : 'Đã hủy ${order.orderCode}');
      }
      return true;
    } catch (e) {
      if (context.mounted) _toast(context, _error(e));
      return false;
    }
  }

  /// Bỏ món (O16): chọn số ly bỏ + lý do.
  static Future<void> removeItem(BuildContext context, Order order, int index) async {
    final item = order.items[index];
    if (order.items.length == 1 && item.quantity == 1) {
      _toast(context, 'Đây là món cuối cùng – muốn bỏ hết thì hủy đơn');
      return;
    }
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RemoveItemSheet(
        item: item,
        // Không được bỏ hết dòng nếu đó là dòng duy nhất.
        maxQuantity: order.items.length == 1 ? item.quantity - 1 : item.quantity,
        paid: order.paymentStatus == PaymentStatus.paid,
      ),
    );
    if (result == null || !context.mounted) return;
    final (by, role) = _actor(context);
    try {
      await StaffOrderService.removeItem(
        orderId: order.id,
        index: index,
        quantity: result.$1,
        reason: result.$2,
        by: by,
        role: role,
      );
      if (context.mounted) {
        _toast(context, 'Đã bỏ ${item.displayName} × ${result.$1}');
      }
    } catch (e) {
      if (context.mounted) _toast(context, _error(e));
    }
  }
}

class _RemoveItemSheet extends StatefulWidget {
  final OrderItem item;
  final int maxQuantity;
  final bool paid;

  const _RemoveItemSheet({
    required this.item,
    required this.maxQuantity,
    required this.paid,
  });

  @override
  State<_RemoveItemSheet> createState() => _RemoveItemSheetState();
}

class _RemoveItemSheetState extends State<_RemoveItemSheet> {
  late int _qty = widget.maxQuantity;
  String _reason = StaffOrderService.removeReasons.first;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _finalReason =>
      _reason == 'Khác' ? _other.text.trim() : _reason;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final amount = item.unitPrice * _qty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bỏ ${item.displayName}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Chỉ bỏ món khi khách đã đồng ý.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('Số ly bỏ')),
                  IconButton(
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_qty / ${item.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed:
                        _qty < widget.maxQuantity ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Text(
                'Tổng đơn giảm ${formatMoney(amount)}'
                '${widget.paid ? ' – số này sẽ được ghi vào "Cần hoàn tiền"' : ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v ?? _reason),
                child: Column(
                  children: [
                    for (final r in StaffOrderService.removeReasons)
                      RadioListTile<String>(
                        value: r,
                        title: Text(r),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              if (_reason == 'Khác')
                TextField(
                  controller: _other,
                  autofocus: true,
                  maxLength: 200,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Nhập lý do'),
                ),
              const SizedBox(height: 12),
              MeowPrimaryButton(
                label: 'Bỏ $_qty ly',
                solidColor: AppColors.danger,
                onPressed: _finalReason.isEmpty
                    ? null
                    : () => Navigator.pop(context, (_qty, _finalReason)),
              ),
              const SizedBox(height: 8),
              MeowSecondaryButton(
                label: 'Quay lại',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
