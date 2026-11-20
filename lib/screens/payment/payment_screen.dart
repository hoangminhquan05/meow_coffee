import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/env_config.dart';
import '../../providers/cart_provider.dart';
import '../../services/invoice_pdf_service.dart';
import '../../utils/formatters.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color _primaryColor = Color(0xFFA50064);
  static const Color _lightGray = Color(0xFFF9F9F9);

  String _userName = 'Đang tải...';
  late final String _currentDate;
  String _paymentMethod = 'Tiền mặt';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _userName = 'Không rõ');
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('uSer').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _userName = (doc.data()?['name'] as String?) ?? 'Không rõ';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _userName = 'Lỗi tải tên');
      }
    }
  }

  String _buildVietQrUrl(double totalPrice) {
    final baseUrl = EnvConfig.vietQrApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final bankBin = EnvConfig.vietQrBankBin;
    final accountNumber = EnvConfig.vietQrAccountNumber;
    final accountName = EnvConfig.vietQrAccountName;
    final templateId = EnvConfig.vietQrTemplateId;
    final amount = totalPrice.toInt();
    final note =
        'COFFEE${_currentDate.replaceAll('/', '').replaceAll(':', '').replaceAll(' ', '')}';

    final encodedNote = Uri.encodeComponent(note);
    final encodedAccountName = Uri.encodeComponent(accountName);
    return '$baseUrl/$bankBin-$accountNumber-$templateId.jpg'
        '?accountName=$encodedAccountName&amount=$amount&addInfo=$encodedNote';
  }

  Future<void> _processPayment() async {
    final cart = context.read<CartProvider>();
    if (cart.cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giỏ hàng trống, không thể thanh toán!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final invoiceItems = List<CartItem>.from(cart.cartItems);
    final invoiceTotal = cart.totalPrice;
    final currentTime = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final productsPayload = invoiceItems
        .map(
          (item) => {
            'product_id': item.product.id,
            'product_name': item.product.name,
            'price': item.product.price,
            'quantity': item.quantity,
          },
        )
        .toList();

    try {
      final orderRef =
          FirebaseFirestore.instance.collection('order_history').doc();
      await orderRef.set({
        'order_id': orderRef.id,
        'paymentMethod': _paymentMethod,
        'total': invoiceTotal,
        'time': currentTime,
        'seller_id': userId,
        'user_name': _userName,
        'products': productsPayload,
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      await _showInvoiceDialog(invoiceItems, invoiceTotal);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi thanh toán: $e')),
      );
    }
  }

  Future<void> _showVietQrDialog(double totalPrice) async {
    final qrUrl = _buildVietQrUrl(totalPrice);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'THANH TOÁN BẰNG VIETQR',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: CachedNetworkImage(
                  imageUrl: qrUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, _) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, _, _) => Image.asset(
                    'assets/images/momo_qr.jpg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Số tiền: ${formatVnd(totalPrice)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nội dung: COFFEE $_currentDate',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hướng dẫn:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const Text(
                'Mở ứng dụng thanh toán và quét mã QR',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _processPayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'XÁC NHẬN ĐÃ THANH TOÁN',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'HỦY BỎ',
                style: TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInvoiceDialog(
    List<CartItem> invoiceItems,
    double invoiceTotal,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _primaryColor.withValues(alpha: 0.2)),
        ),
        title: const Text(
          'HÓA ĐƠN THANH TOÁN',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: _primaryColor,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'MEOW COFFEE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Địa chỉ: 83 Hai Bà Trưng, Hoàn Kiếm, TP.Hà Nội',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
                const Text('Điện thoại: 032 8386 66',
                    style: TextStyle(fontSize: 13)),
                const Divider(height: 20),
                Text('Nhân viên: $_userName',
                    style: const TextStyle(fontSize: 15)),
                Text('Ngày: $_currentDate',
                    style: const TextStyle(fontSize: 15)),
                const Divider(height: 20),
                const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Sản phẩm',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'SL',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Thành tiền',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...invoiceItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'x${item.quantity}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatVnd(item.totalPrice),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tổng tiền:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      formatVnd(invoiceTotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Phương thức thanh toán: $_paymentMethod'),
                const SizedBox(height: 12),
                const Text(
                  'Cảm ơn quý khách!',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final file = await InvoicePdfService.generateAndSave(
                        items: invoiceItems,
                        totalPrice: invoiceTotal,
                        userName: _userName,
                        currentDate: _currentDate,
                        paymentMethod: _paymentMethod,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã lưu hóa đơn PDF vào ${file.path}'),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi khi lưu PDF: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Lưu PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    context.read<CartProvider>().clearCart();
                    _showCompletionDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Hoàn tất',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCompletionDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _primaryColor.withValues(alpha: 0.2)),
        ),
        title: const Text(
          'THANH TOÁN THÀNH CÔNG',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: _primaryColor,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 64),
            SizedBox(height: 16),
            Text(
              'Hoàn Tất Đơn Hàng',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SizedBox(height: 12),
            Text(
              'Cảm Ơn Quý Khách Đã Ghé Thăm Meow Coffee',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            SizedBox(height: 4),
            Text(
              'Xin Chào Và Hẹn Gặp Lại Quý Khách!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/cart',
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hóa đơn thanh toán',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: _primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Column(
                children: [
                  Text(
                    'MEOW COFFEE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text('Địa chỉ: 83 Hai Bà Trưng, Hoàn Kiếm, TP.Hà Nội'),
                  Text('Điện thoại: 032 8386 66'),
                ],
              ),
            ),
            const Divider(height: 28),
            Text('👩‍💼 Nhân viên: $_userName',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text('📅 Ngày bán: $_currentDate',
                style: const TextStyle(fontSize: 16)),
            const Divider(height: 24),
            const Text(
              '🛍️ Sản phẩm:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...cart.cartItems.map(
              (item) => Card(
                color: _lightGray,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${item.product.name} x${item.quantity}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        formatVnd(item.totalPrice),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '💵 Tổng tiền:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatVnd(cart.totalPrice),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '💳 Phương thức thanh toán:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            RadioGroup<String>(
              groupValue: _paymentMethod,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _paymentMethod = value);
                }
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    title: Text('Tiền mặt'),
                    value: 'Tiền mặt',
                    activeColor: _primaryColor,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: Text('Thanh Toán Qua VietQR (QR Code)'),
                    value: 'VietQR',
                    activeColor: _primaryColor,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (_paymentMethod == 'VietQR')
              const Padding(
                padding: EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'Vui lòng mở ứng dụng ngân hàng và quét mã QR',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        if (_paymentMethod == 'VietQR') {
                          _showVietQrDialog(cart.totalPrice);
                        } else {
                          _processPayment();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'XÁC NHẬN THANH TOÁN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
