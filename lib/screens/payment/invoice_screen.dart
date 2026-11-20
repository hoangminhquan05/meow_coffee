import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cart_provider.dart';
import '../../services/invoice_pdf_service.dart';
import '../../utils/formatters.dart';

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

  static const Color _primaryColor = Color(0xFFA50064);

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HÓA ĐƠN THANH TOÁN',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: _primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(context, '/cart'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MEOW COFFEE',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
            const Text('Địa chỉ: 83 Hai Bà Trưng, Hoàn Kiếm, TP.Hà Nội'),
            const Text('Điện thoại: 032 8386 66'),
            const Divider(height: 28),
            Text('👩‍💼 Nhân viên: $userName',
                style: const TextStyle(fontSize: 16)),
            Text('📅 Ngày bán: $currentDate',
                style: const TextStyle(fontSize: 16)),
            const Divider(height: 24),
            const Text(
              '🛍️ Sản phẩm:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...cart.cartItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('${item.product.name} x${item.quantity}'),
                    ),
                    Text(formatVnd(item.totalPrice)),
                  ],
                ),
              ),
            ),
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '💵 Tổng tiền:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  formatVnd(cart.totalPrice),
                  style: const TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '💳 Phương thức thanh toán: $paymentMethod',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
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
                            SnackBar(
                              content: Text('Đã xuất hóa đơn: ${file.path}'),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi xuất PDF: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Xuất Hóa Đơn',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/cart'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Về Giỏ Hàng',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
