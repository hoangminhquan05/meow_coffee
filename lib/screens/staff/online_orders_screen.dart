import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../models/shipper_status.dart';
import '../../providers/online_orders_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/staff_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/meow_ui.dart';
import '../online/my_orders_screen.dart' show StatusChip;
import 'dispatch_widgets.dart';
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

  // Tab "Giao thành công": đơn giao xong hôm nay (đổi ngày thì nghe lại).
  StreamSubscription<List<Order>>? _doneSub;
  String _doneDay = '';
  List<Order>? _done;
  Object? _doneError;

  @override
  void initState() {
    super.initState();
    _watchDone();
    // Cập nhật "x phút trước" và sang ngày mới.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _watchDone();
      setState(() {});
    });
  }

  void _watchDone() {
    final now = DateTime.now();
    final day = ShipperStatus.dayKey(now);
    if (day == _doneDay) return;
    _doneDay = day;
    _doneSub?.cancel();
    _doneSub = StaffOrderService.watchDeliveredOn(now).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _done = list;
          _doneError = null;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _doneError = e);
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _doneSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OnlineOrdersProvider>();
    return DefaultTabController(
      length: _columns.length + 1,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        bottomNavigationBar: const BottomNavBar(currentIndex: 3),
        appBar: AppBar(
          title: const Text('Đơn Online'),
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.bg,
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/shippers_live'),
              icon: const Icon(Icons.delivery_dining_rounded, color: AppColors.brand),
              label: Text(
                'Shipper (${context.watch<ShopSettingsProvider>().shippersOnShift ?? 0})',
                style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
          ],
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
              Tab(child: _TabLabel('Giao thành công', _done?.length ?? 0)),
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
              _DeliveredList(orders: _done, error: _doneError),
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

/// Tab "Giao thành công": đơn giao xong hôm nay, mỗi thẻ là chi tiết đơn.
class _DeliveredList extends StatelessWidget {
  final List<Order>? orders;
  final Object? error;

  const _DeliveredList({required this.orders, required this.error});

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Lỗi tải đơn đã giao: $error',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
        ),
      );
    }
    final list = orders;
    if (list == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }
    if (list.isEmpty) {
      return const Center(
        child: Text('Hôm nay chưa có đơn giao thành công',
            style: TextStyle(color: AppColors.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _DeliveredOrderCard(key: ValueKey(list[i].id), order: list[i]),
    );
  }
}

class _DeliveredOrderCard extends StatelessWidget {
  final Order order;

  const _DeliveredOrderCard({super.key, required this.order});

  String _time(DateTime? t) => t == null ? '–' : formatDateTime(t).split(' ').last;

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    final took = d?.pickedUpAt != null && d?.deliveredAt != null
        ? d!.deliveredAt!.difference(d.pickedUpAt!).inMinutes
        : null;
    const label = TextStyle(fontSize: 12, color: AppColors.muted);
    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.pushNamed(context, '/online_order', arguments: order.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 6),
              Text(order.orderCode,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('Giao lúc ${_time(d?.deliveredAt)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const Divider(height: 18),
          // Giao cho ai
          Text('${d?.receiverName ?? order.customer?.name ?? ''} · ${d?.receiverPhone ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(d?.addressText ?? '', style: const TextStyle(fontSize: 13, height: 1.35)),
          if ((d?.note ?? '').isNotEmpty)
            Text('Ghi chú cho shipper: ${d!.note}',
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          // Món
          for (final i in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${i.displayName} × ${i.quantity}'
                      '${i.note.isNotEmpty ? '\n   Ghi chú: ${i.note}' : ''}',
                      style: const TextStyle(fontSize: 13.5, height: 1.35),
                    ),
                  ),
                  Text(formatMoney(i.lineTotal), style: const TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
          for (final c in order.itemChanges)
            Text('Đã bỏ ${c.displayName} × ${c.quantity} · ${c.reason}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
          if (order.note.isNotEmpty)
            Text('Ghi chú đơn: ${order.note}',
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
          const Divider(height: 18),
          Row(
            children: [
              const Text('Tổng đơn', style: label),
              const Spacer(),
              Text(formatMoney(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
            ],
          ),
          if (order.extraFees.isNotEmpty)
            Text('Gồm ${order.extraFees.map((f) => '${f.label.toLowerCase()} ${formatMoney(f.amount)}').join(', ')}',
                style: label),
          const SizedBox(height: 4),
          // Shipper + tiền đã thu
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${d?.shipper?.name ?? 'Shipper'}'
                  ' · lấy hàng ${_time(d?.pickedUpAt)}'
                  '${took != null ? ' · đi $took phút' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  size: 18,
                  color: order.codAmount > 0 ? AppColors.warning : AppColors.success),
              const SizedBox(width: 6),
              Text(
                order.codAmount > 0
                    ? 'Shipper đã thu ${formatMoney(order.codAmount)}'
                        '${order.paymentMethod == PaymentMethod.cash ? ' (COD)' : ' (phí giao lại)'}'
                    : 'Đã trả trước (VietQR) – không thu tiền',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: order.codAmount > 0 ? AppColors.warning : AppColors.success),
              ),
            ],
          ),
        ],
      ),
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
          if (order.status == OrderStatus.ready ||
              order.status == OrderStatus.delivering ||
              order.status == OrderStatus.deliveryFailed) ...[
            const SizedBox(height: 6),
            DispatchInfo(order: order),
          ],
          if (order.status == OrderStatus.ready &&
              order.delivery?.shipper == null &&
              order.dispatch?.state == DispatchState.noShipper) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MeowSecondaryButton(
                    label: 'Mời lại',
                    height: 40,
                    icon: Icons.refresh_rounded,
                    onPressed: _busy
                        ? null
                        : () => _run(() => OnlineOrderActions.retry(context, order)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MeowPrimaryButton(
                    label: 'Gán shipper',
                    height: 40,
                    onPressed: _busy
                        ? null
                        : () => _run(() => OnlineOrderActions.assign(context, order)),
                  ),
                ),
              ],
            ),
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
