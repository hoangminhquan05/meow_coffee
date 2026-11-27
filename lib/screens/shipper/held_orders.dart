import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/chat.dart';
import '../../models/order.dart';
import '../../providers/chat_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/online_order_service.dart';
import '../../services/shipper_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/chat_buttons.dart';
import '../../widgets/meow_ui.dart';

/// Đơn shipper đang giữ (theo `shipper_status.active_order_ids`), xếp theo
/// thứ tự giao gợi ý. Lấy hàng từng đơn, hoặc "Lấy tất cả" khi các đơn đều Sẵn sàng.
class HeldOrders extends StatefulWidget {
  final List<String> orderIds;

  const HeldOrders({super.key, required this.orderIds});

  @override
  State<HeldOrders> createState() => _HeldOrdersState();
}

class _HeldOrdersState extends State<HeldOrders> {
  final _subs = <String, StreamSubscription<Order?>>{};
  final _orders = <String, Order>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HeldOrders oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final ids = widget.orderIds.toSet();
    for (final id in _subs.keys.toList()) {
      if (!ids.contains(id)) {
        _subs.remove(id)?.cancel();
        _orders.remove(id);
      }
    }
    for (final id in ids) {
      _subs.putIfAbsent(
        id,
        () => ShipperOrderService.watchOrder(id).listen(
          (o) {
            if (!mounted) return;
            setState(() => o == null ? _orders.remove(id) : _orders[id] = o);
          },
          onError: (Object e) {
            // Quán đã chuyển đơn cho người khác → không còn quyền đọc.
            if (mounted) setState(() => _orders.remove(id));
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _pickAll(List<Order> ready) async {
    setState(() => _busy = true);
    try {
      for (final o in ready) {
        await ShipperOrderService.pickedUp(o.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Đã lấy ${ready.length} đơn – bắt đầu giao')));
      }
    } on OnlineOrderError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopSettingsProvider>().settings.location;
    final list = ShipperOrderService.suggestRoute(
      shop,
      widget.orderIds.map((id) => _orders[id]).whereType<Order>().toList(),
    );
    final ready = list.where((o) => o.status == OrderStatus.ready).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ĐƠN ĐANG GIỮ (${widget.orderIds.length})',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              ),
            ),
            if (ready.length >= 2)
              TextButton.icon(
                onPressed: _busy ? null : () => _pickAll(ready),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text('Lấy tất cả (${ready.length})'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (widget.orderIds.isEmpty)
          const MeowCard(
            padding: EdgeInsets.all(16),
            child: Text('Chưa có đơn nào. Khi có đơn mới, lời mời sẽ hiện toàn màn hình.',
                style: TextStyle(color: AppColors.inkSlate)),
          ),
        if (list.length > 1)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Thứ tự giao gợi ý (lộ trình ngắn nhất từ quán):',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HeldOrderCard(order: list[i], index: list.length > 1 ? i + 1 : null),
          ),
      ],
    );
  }
}

class _HeldOrderCard extends StatelessWidget {
  final Order order;
  final int? index;

  const _HeldOrderCard({required this.order, this.index});

  @override
  Widget build(BuildContext context) {
    final collect = order.amountToCollect;
    final delivering = order.status == OrderStatus.delivering;
    return MeowCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).pushNamed('/shipper_order', arguments: order.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (index != null) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.brand,
                  child: Text('$index',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(order.orderCode, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: delivering ? AppColors.soft : AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(delivering ? 'Đang giao' : 'Chờ lấy hàng',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: delivering ? AppColors.brand : AppColors.warning)),
                        ),
                        const Spacer(),
                        // Khách nhắn chưa đọc.
                        Builder(builder: (context) {
                          final unread = context.select<ChatProvider, int>(
                              (c) => c.unreadOf(ChatRef.order(order.id)));
                          if (unread == 0) return const SizedBox.shrink();
                          return CountBadge(
                            count: unread,
                            child: const Icon(Icons.chat_bubble_rounded,
                                size: 20, color: AppColors.brand),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(order.delivery?.addressText ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.inkSlate, height: 1.3)),
                    const SizedBox(height: 4),
                    Text(
                      collect > 0 ? 'Thu ${formatMoney(collect)}' : 'Đã trả trước',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: collect > 0 ? AppColors.warning : AppColors.success),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
