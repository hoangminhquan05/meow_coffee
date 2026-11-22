import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/date_range_bar.dart';
import '../../widgets/meow_ui.dart';

/// Lịch sử đơn (L9). Nhân viên: đơn của mình; admin: tất cả.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  DayRange _range = DayRange.today();
  OrderStatus? _status; // null = tất cả
  PaymentMethod? _method;
  String? _sellerId; // admin lọc theo nhân viên
  Stream<List<Order>>? _stream;
  String? _streamKey;

  Stream<List<Order>> _ordersStream(SessionProvider session) {
    final sellerFilter = session.isAdmin ? null : session.uid;
    final key = '${_range.from}|${_range.to}|$sellerFilter';
    if (_stream == null || key != _streamKey) {
      _streamKey = key;
      _stream = OrderService.watchOrders(
        from: _range.from,
        to: _range.to,
        sellerId: sellerFilter,
      );
    }
    return _stream!;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Lịch Sử Đơn Hàng'),
      body: StreamBuilder<List<Order>>(
        stream: _ordersStream(session),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Order>[];
          final sellers = <String, String>{
            for (final o in all)
              if (o.seller != null) o.seller!.id: o.seller!.name,
          };
          final orders = all.where((o) {
            if (_status != null && o.status != _status) return false;
            if (_method != null && o.paymentMethod != _method) return false;
            if (_sellerId != null && o.seller?.id != _sellerId) return false;
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DateRangeBar(
                value: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DropdownChip<OrderStatus?>(
                    label: 'Trạng thái',
                    value: _status,
                    items: const {
                      null: 'Tất cả',
                      OrderStatus.completed: 'Hoàn tất',
                      OrderStatus.cancelled: 'Đã hủy',
                    },
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  _DropdownChip<PaymentMethod?>(
                    label: 'Thanh toán',
                    value: _method,
                    items: {
                      null: 'Tất cả',
                      for (final m in PaymentMethod.values) m: m.label,
                    },
                    onChanged: (v) => setState(() => _method = v),
                  ),
                  if (session.isAdmin)
                    _DropdownChip<String?>(
                      label: 'Nhân viên',
                      value: sellers.containsKey(_sellerId) ? _sellerId : null,
                      items: {null: 'Tất cả', ...sellers},
                      onChanged: (v) => setState(() => _sellerId = v),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (snapshot.hasError)
                Text(
                  'Lỗi tải đơn: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.danger),
                )
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  ),
                )
              else if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Không có đơn nào',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              else ...[
                Text(
                  '${orders.length} đơn',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                for (final o in orders) ...[
                  OrderListTile(order: o, showSeller: session.isAdmin),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Một dòng đơn: mã, giờ, loại đơn/bàn, tổng tiền, trạng thái.
class OrderListTile extends StatelessWidget {
  final Order order;
  final bool showSeller;

  const OrderListTile({super.key, required this.order, this.showSeller = false});

  @override
  Widget build(BuildContext context) {
    final cancelled = order.isCancelled;
    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: () =>
          Navigator.pushNamed(context, '/order_detail', arguments: order.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      order.orderCode,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: cancelled ? AppColors.muted : AppColors.ink,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (cancelled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Đã hủy',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatDateTime(order.createdAt)} · ${order.fulfillmentLabel}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(
                  [
                    '${order.totalItems} món',
                    order.paymentMethod.label,
                    if (showSeller && order.seller != null) order.seller!.name,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(order.total),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cancelled ? AppColors.muted : AppColors.brand,
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  const _DropdownChip({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return PopupMenuButton<T>(
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in items.entries)
          PopupMenuItem<T>(value: e.key, child: Text(e.value)),
      ],
      child: Chip(
        backgroundColor: active ? AppColors.soft : AppColors.surface,
        side: BorderSide(color: active ? AppColors.brand : AppColors.border),
        label: Text(
          active ? '$label: ${items[value]}' : label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.brand : AppColors.ink,
          ),
        ),
        deleteIcon: const Icon(Icons.arrow_drop_down_rounded),
        onDeleted: null,
        avatar: const Icon(Icons.filter_list_rounded, size: 16),
      ),
    );
  }
}
