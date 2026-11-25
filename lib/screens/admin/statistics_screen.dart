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
import '../orders/order_history_screen.dart' show OrderListTile;

/// Thống kê doanh thu (L12). Doanh thu = tổng `total` của đơn `completed`.
/// Nhân viên chỉ thấy đơn của mình; admin thấy tất cả và lọc theo nhân viên.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  DayRange _range = DayRange.today();
  String? _sellerId;
  OrderChannel? _channel;
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
      appBar: MeowHeader(
        title: session.isAdmin ? 'Thống Kê Doanh Thu' : 'Doanh Thu Của Tôi',
      ),
      body: StreamBuilder<List<Order>>(
        stream: _ordersStream(session),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Order>[];
          final sellers = <String, String>{
            for (final o in all)
              if (o.seller != null) o.seller!.id: o.seller!.name,
          };
          final orders = all.where((o) {
            if (_sellerId != null && o.seller?.id != _sellerId) return false;
            if (_channel != null && o.channel != _channel) return false;
            if (o.isOnline && o.status == OrderStatus.awaitingPayment) return false;
            return true;
          }).toList();
          final stats = _Stats.from(orders);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DateRangeBar(
                value: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
              if (session.isAdmin) ...[
                const SizedBox(height: 10),
                SegmentedButton<OrderChannel?>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: null, label: Text('Tất cả')),
                    ButtonSegment(value: OrderChannel.inStore, label: Text('Tại quán')),
                    ButtonSegment(value: OrderChannel.online, label: Text('Online')),
                  ],
                  selected: {_channel},
                  onSelectionChanged: (s) => setState(() => _channel = s.first),
                ),
              ],
              if (session.isAdmin && sellers.isNotEmpty && _channel != OrderChannel.online) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue:
                      sellers.containsKey(_sellerId) ? _sellerId : null,
                  decoration: InputDecoration(
                    labelText: 'Nhân viên',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    for (final e in sellers.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _sellerId = v),
                ),
              ],
              const SizedBox(height: 14),
              if (snapshot.hasError)
                Text(
                  'Lỗi tải dữ liệu: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.danger),
                )
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  ),
                )
              else ...[
                _RevenueCard(stats: stats),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Đơn hoàn tất',
                        value: '${stats.completedCount}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'TB / đơn',
                        value: formatMoney(stats.averageOrder),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'Đơn đã hủy',
                        value: '${stats.cancelledCount}',
                        danger: stats.cancelledCount > 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _BreakdownCard(
                  title: 'THEO PHƯƠNG THỨC THANH TOÁN',
                  rows: {
                    for (final m in PaymentMethod.values)
                      m.label: stats.byMethod[m] ?? 0,
                  },
                  total: stats.revenue,
                ),
                const SizedBox(height: 12),
                _BreakdownCard(
                  title: 'THEO LOẠI ĐƠN',
                  rows: {
                    Fulfillment.dineIn.label:
                        stats.byFulfillment[Fulfillment.dineIn] ?? 0,
                    Fulfillment.takeaway.label:
                        stats.byFulfillment[Fulfillment.takeaway] ?? 0,
                    if (session.isAdmin)
                      'Giao hàng (online)':
                          stats.byFulfillment[Fulfillment.delivery] ?? 0,
                  },
                  total: stats.revenue,
                ),
                const SizedBox(height: 12),
                _TopProductsCard(top: stats.topProducts),
                const SizedBox(height: 18),
                const Text(
                  'ĐƠN HÀNG',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (orders.isEmpty)
                  const Text(
                    'Không có đơn trong khoảng thời gian này',
                    style: TextStyle(color: AppColors.muted),
                  )
                else
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

class _Stats {
  final int revenue;
  final int completedCount;
  final int cancelledCount;
  final Map<PaymentMethod, int> byMethod;
  final Map<Fulfillment, int> byFulfillment;
  final List<MapEntry<String, int>> topProducts; // tên → số lượng

  _Stats({
    required this.revenue,
    required this.completedCount,
    required this.cancelledCount,
    required this.byMethod,
    required this.byFulfillment,
    required this.topProducts,
  });

  int get averageOrder => completedCount == 0 ? 0 : revenue ~/ completedCount;

  factory _Stats.from(List<Order> orders) {
    var revenue = 0, completed = 0, cancelled = 0;
    final byMethod = <PaymentMethod, int>{};
    final byFulfillment = <Fulfillment, int>{};
    final qtyById = <String, int>{};
    final nameById = <String, String>{};
    for (final o in orders) {
      if (o.status == OrderStatus.cancelled) {
        cancelled++;
        continue;
      }
      if (o.status != OrderStatus.completed) continue;
      completed++;
      revenue += o.total;
      byMethod[o.paymentMethod] = (byMethod[o.paymentMethod] ?? 0) + o.total;
      byFulfillment[o.fulfillment] =
          (byFulfillment[o.fulfillment] ?? 0) + o.total;
      for (final i in o.items) {
        qtyById[i.productId] = (qtyById[i.productId] ?? 0) + i.quantity;
        nameById[i.productId] = i.name;
      }
    }
    final top = qtyById.entries
        .map((e) => MapEntry(nameById[e.key] ?? e.key, e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Stats(
      revenue: revenue,
      completedCount: completed,
      cancelledCount: cancelled,
      byMethod: byMethod,
      byFulfillment: byFulfillment,
      topProducts: top.take(5).toList(),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final _Stats stats;

  const _RevenueCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.buttonShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DOANH THU',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE9DFFF),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(stats.revenue),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          Text(
            'Không tính ${stats.cancelledCount} đơn đã hủy',
            style: const TextStyle(fontSize: 12, color: Color(0xFFEEE6FF)),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool danger;

  const _MiniStat({
    required this.label,
    required this.value,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: danger ? AppColors.danger : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String title;
  final Map<String, int> rows;
  final int total;

  const _BreakdownCard({
    required this.title,
    required this.rows,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          for (final e in rows.entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(e.key,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.inkSlate)),
                ),
                Text(
                  formatMoney(e.value),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    total == 0 ? '0%' : '${(e.value * 100 / total).round()}%',
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : e.value / total,
                minHeight: 6,
                backgroundColor: AppColors.soft,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  final List<MapEntry<String, int>> top;

  const _TopProductsCard({required this.top});

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'MÓN BÁN CHẠY',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const Text('Chưa có dữ liệu',
                style: TextStyle(color: AppColors.muted))
          else
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.soft,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(top[i].key)),
                    Text(
                      '${top[i].value} ly',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
