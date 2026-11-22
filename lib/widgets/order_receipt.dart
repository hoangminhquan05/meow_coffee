import 'package:flutter/material.dart';

import '../core/enums.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Nội dung hóa đơn của một đơn (L7) – dùng ở dialog sau thanh toán
/// và màn chi tiết đơn.
class OrderReceiptView extends StatelessWidget {
  final Order order;

  const OrderReceiptView({super.key, required this.order});

  static const _meta = TextStyle(fontSize: 12.5, color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'MEOW COFFEE',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.brand,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '83 Hai Bà Trưng, Hoàn Kiếm, TP. Hà Nội\nHotline: 032 8386 66',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        // Mã đơn to, dễ đọc khi gọi khách lấy món.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: order.isCancelled ? AppColors.dangerSoft : AppColors.soft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                order.isCancelled ? 'MÃ ĐƠN · ĐÃ HỦY' : 'MÃ ĐƠN',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: order.isCancelled ? AppColors.danger : AppColors.muted,
                ),
              ),
              Text(
                order.orderCode,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: order.isCancelled ? AppColors.danger : AppColors.brand,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Loại đơn: ${order.fulfillmentLabel}', style: _meta),
        Text('Thu ngân: ${order.seller?.name ?? ''}', style: _meta),
        Text('Thời gian: ${formatDateTime(order.createdAt)}', style: _meta),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: AppColors.border),
        ),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.displayName} × ${item.quantity}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (item.note.isNotEmpty)
                        Text(
                          item.note,
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(item.lineTotal),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        if (order.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ghi chú đơn: ${order.note}',
            style: const TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: AppColors.inkSlate,
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: AppColors.border),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tổng cộng',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              formatMoney(order.total),
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Thanh toán: ${order.paymentMethod.label}', style: _meta),
        if (order.paymentMethod == PaymentMethod.vietqr &&
            order.paymentRef != null)
          Text('Nội dung CK: ${order.paymentRef}', style: _meta),
        if (order.isCancelled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Đã hủy bởi ${order.cancelledBy?.name ?? ''} lúc '
              '${formatDateTime(order.cancelledAt)}\n'
              'Lý do: ${order.cancelReason ?? ''}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.danger,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
