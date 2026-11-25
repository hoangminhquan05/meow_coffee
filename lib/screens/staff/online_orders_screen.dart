import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../providers/online_orders_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/meow_ui.dart';
import '../online/my_orders_screen.dart' show StatusChip;
import 'online_order_actions.dart';

/// Một tab của màn Đơn online (O14).
class _Column {
  final String label;
  final Set<OrderStatus> statuses;
  final String empty;

  const _Column(this.label, this.statuses, this.empty);
}

const _columns = [
  _Column('Chờ xác nhận', {OrderStatus.pending}, 'Chưa có đơn mới'),
  _Column('Đang pha', {OrderStatus.confirmed, OrderStatus.preparing},
      'Không có đơn đang pha'),
  _Column('Sẵn sàng', {OrderStatus.ready}, 'Không có đơn chờ giao'),
  _Column('Đang giao', {OrderStatus.delivering}, 'Không có đơn đang giao'),
  _Column('Giao thất bại', {OrderStatus.deliveryFailed},
      'Không có đơn giao thất bại'),
];

/// Màn "Đơn online" cho NV/admin: tab theo trạng thái, cũ nhất ở trên.
class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Cập nhật "x phút trước".
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OnlineOrdersProvider>();
    return DefaultTabController(
      length: _columns.length,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        bottomNavigationBar: const BottomNavBar(currentIndex: 3),
        appBar: AppBar(
          title: const Text('Đơn Online'),
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.bg,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.brand,
            indicatorColor: AppColors.brand,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              for (final c in _columns)
                Tab(child: _TabLabel(c.label, provider.byStatuses(c.statuses).length,
                    highlight: c.statuses.contains(OrderStatus.pending))),
            ],
          ),
        ),
        body: Builder(builder: (context) {
          if (provider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Lỗi tải đơn: ${provider.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    MeowSecondaryButton(label: 'Thử lại', onPressed: provider.retry),
                  ],
                ),
              ),
            );
          }
          if (!provider.isLoaded) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          return TabBarView(
            children: [
              for (final c in _columns)
                _OrderList(orders: provider.byStatuses(c.statuses), empty: c.empty),
            ],
          );
        }),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final int count;
  final bool highlight;

  const _TabLabel(this.label, this.count, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: highlight ? AppColors.danger : AppColors.soft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: highlight ? Colors.white : AppColors.brand,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final String empty;

  const _OrderList({required this.orders, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(empty, style: const TextStyle(color: AppColors.muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          OnlineOrderCard(key: ValueKey(orders[i].id), order: orders[i]),
    );
  }
}

/// "vừa xong", "5 phút trước", "1 giờ 20 phút trước".
String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút trước';
  final m = d.inMinutes % 60;
  return '${d.inHours} giờ${m > 0 ? ' $m phút' : ''} trước';
}

/// Thẻ đơn: mã, thời gian chờ, món, tiền, nút bước tiếp theo.
class OnlineOrderCard extends StatefulWidget {
  final Order order;

  const OnlineOrderCard({super.key, required this.order});

  @override
  State<OnlineOrderCard> createState() => _OnlineOrderCardState();
}

class _OnlineOrderCardState extends State<OnlineOrderCard> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final next = nextStepLabel(order.status);
    final since = order.timeOf(order.status) ?? order.createdAt;
    final items = order.items.map((i) => '${i.displayName} ×${i.quantity}').join(', ');
    final paid = order.paymentStatus == PaymentStatus.paid;

    return MeowCard(
      padding: const EdgeInsets.all(14),
      borderColor: order.status == OrderStatus.pending ? AppColors.brand : null,
      onTap: () => Navigator.pushNamed(context, '/online_order', arguments: order.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(order.orderCode,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(timeAgo(since),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
              StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${order.customer?.name ?? ''} · '
            '${(order.delivery?.distanceKm ?? 0).toStringAsFixed(1).replaceAll('.', ',')} km',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(items,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSlate)),
          if (order.note.isNotEmpty)
            Text('Ghi chú: ${order.note}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(formatMoney(order.total),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brand)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.paymentMethod == PaymentMethod.cash
                      ? 'COD – thu khi giao'
                      : (paid ? 'VietQR – đã trả' : 'VietQR'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: paid ? AppColors.success : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          if (order.status == OrderStatus.ready) ...[
            const SizedBox(height: 6),
            const Text('Chờ shipper nhận đơn',
                style: TextStyle(fontSize: 12.5, color: AppColors.warning)),
          ],
          if (next != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (order.status == OrderStatus.pending) ...[
                  Expanded(
                    child: MeowSecondaryButton(
                      label: 'Từ chối',
                      height: 44,
                      textColor: AppColors.danger,
                      backgroundColor: AppColors.dangerSoft,
                      borderColor: const Color(0xFFFECDD3),
                      onPressed: _busy
                          ? null
                          : () => _run(() => OnlineOrderActions.cancel(context, order)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: MeowPrimaryButton(
                    label: next,
                    height: 44,
                    isLoading: _busy,
                    onPressed: _busy
                        ? null
                        : () => _run(() => OnlineOrderActions.advance(context, order)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
