import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../models/shipper_status.dart';
import '../../providers/session_provider.dart';
import '../../services/shipper_order_service.dart';
import '../../services/shipper_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';
import 'shift_offer_stats.dart';

/// "Hôm nay" của shipper: số đơn đã giao / thất bại, tiền COD đang giữ,
/// danh sách đơn giao xong trong ngày.
class ShipperTodayScreen extends StatelessWidget {
  const ShipperTodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<SessionProvider>().uid;
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Hôm Nay'),
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          StreamBuilder<ShipperStatus>(
            stream: ShipperService.watchMine(uid),
            builder: (context, snap) {
              final s = snap.data ?? ShipperStatus.offShift;
              return Column(
                children: [
                  Row(
                    children: [
                      _Stat(label: 'Đã giao', value: '${s.deliveredToday(now)}', color: AppColors.success),
                      const SizedBox(width: 10),
                      _Stat(label: 'Thất bại', value: '${s.failedToday(now)}', color: AppColors.danger),
                      const SizedBox(width: 10),
                      _Stat(label: 'COD đang giữ', value: formatMoney(s.codHolding), color: AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ShiftOfferStats(uid: uid, shiftId: s.onShift ? s.shiftId : ''),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('ĐƠN ĐÃ GIAO HÔM NAY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
          const SizedBox(height: 8),
          StreamBuilder<List<Order>>(
            stream: ShipperOrderService.watchDoneToday(uid, now),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Không tải được danh sách: ${snap.error}',
                    style: const TextStyle(color: AppColors.danger));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.brand));
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return const MeowCard(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa giao đơn nào hôm nay.', style: TextStyle(color: AppColors.muted)),
                );
              }
              return Column(
                children: [
                  for (final o in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: MeowCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.success),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.orderCode, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(o.delivery?.addressText ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatDateTime(o.delivery?.deliveredAt).split(' ').last,
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                Text(o.codAmount > 0 ? 'Thu ${formatMoney(o.codAmount)}' : 'Trả trước',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: MeowCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              FittedBox(
                child: Text(value,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      );
}
