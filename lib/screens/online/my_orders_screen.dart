import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/session_provider.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

/// Tab "Đơn của tôi": Đang xử lý / Lịch sử, cập nhật realtime (bước 5).
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  late Stream<List<Order>> _stream = _subscribe();

  Stream<List<Order>> _subscribe() =>
      OrderService.watchCustomerOrders(context.read<SessionProvider>().uid);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Đơn Của Tôi'),
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.bg,
          bottom: const TabBar(
            labelColor: AppColors.brand,
            indicatorColor: AppColors.brand,
            tabs: [Tab(text: 'Đang xử lý'), Tab(text: 'Lịch sử')],
          ),
        ),
        body: StreamBuilder<List<Order>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              // Ví dụ index đang build: cho thử lại mà không cần mở lại app.
              final building = snap.error.toString().contains('requires an index');
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        building
                            ? 'Hệ thống đang chuẩn bị dữ liệu đơn hàng, vui lòng thử lại sau ít phút.'
                            : 'Không tải được đơn hàng.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => setState(() => _stream = _subscribe()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.brand));
            }
            final all = snap.data!;
            final active = all.where((o) => o.status.isActive).toList();
            final history = all.where((o) => !o.status.isActive).toList();
            return TabBarView(
              children: [
                _List(orders: active, empty: 'Không có đơn đang xử lý'),
                _List(orders: history, empty: 'Chưa có đơn nào'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<Order> orders;
  final String empty;

  const _List({required this.orders, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(empty, style: const TextStyle(color: AppColors.muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => CustomerOrderTile(order: orders[i]),
    );
  }
}

/// Màu nhãn trạng thái đơn online.
Color statusColor(OrderStatus s) {
  switch (s) {
    case OrderStatus.completed:
      return AppColors.success;
    case OrderStatus.cancelled:
    case OrderStatus.deliveryFailed:
      return AppColors.danger;
    case OrderStatus.awaitingPayment:
      return AppColors.warning;
    default:
      return AppColors.brand;
  }
}

class StatusChip extends StatelessWidget {
  final OrderStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

class CustomerOrderTile extends StatelessWidget {
  final Order order;

  const CustomerOrderTile({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final names = order.items.map((i) => '${i.displayName} ×${i.quantity}').join(', ');
    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.pushNamed(context, '/my_order', arguments: order.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(order.orderCode,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(names,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSlate)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(formatDateTime(order.createdAt),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const Spacer(),
              Text(formatMoney(order.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.brand)),
            ],
          ),
        ],
      ),
    );
  }
}
