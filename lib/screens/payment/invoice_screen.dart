import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cart_provider.dart';
import '../../services/invoice_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

class InvoiceScreen extends StatelessWidget {
  final String userName;
  final String currentDate;
  final String paymentMethod;

  const InvoiceScreen({
    super.key,
    required this.userName,
    required this.currentDate,
    required this.paymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: 'Hóa Đơn Thành Công',
        onBack: () => Navigator.pushReplacementNamed(context, '/cart'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MeowCard(
              padding: const EdgeInsets.all(20),
              borderRadius: 24,
              child: const Column(
                children: [
                  Text(
                    'Thanh toán thành công',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16856B),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Đơn hàng đã được ghi nhận trên hệ thống',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MeowCard(
              padding: const EdgeInsets.all(20),
              borderRadius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Column(
                      children: [
                        Text(
                          'MEOW COFFEE',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '83 Hai Bà Trưng, Hoàn Kiếm, TP. Hà Nội\nĐiện thoại: 032 8386 66',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
                  Text(
                    'Nhân viên: $userName',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ngày bán: $currentDate',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'CHI TIẾT ĐƠN HÀNG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...cart.cartItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.product.name} × ${item.quantity}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            formatVnd(item.totalPrice, suffix: 'đ'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng thanh toán',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                      Text(
                        formatVnd(cart.totalPrice, suffix: 'đ'),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Phương thức: $paymentMethod',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MeowPrimaryButton(
              label: 'Xuất hóa đơn PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () async {
                try {
                  final file = await InvoicePdfService.generateAndSave(
                    items: cart.cartItems,
                    totalPrice: cart.totalPrice,
                    userName: userName,
                    currentDate: currentDate,
                    paymentMethod: paymentMethod,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Đã xuất hóa đơn: ${file.path}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi xuất PDF: $e')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            MeowSecondaryButton(
              label: 'Về trang chủ',
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/home',
                (route) => false,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Cảm ơn bạn đã ghé Meow Coffee!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
