import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/env_config.dart';
import '../../providers/cart_provider.dart';
import '../../services/invoice_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
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
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Thanh toán VietQR',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Mở ứng dụng ngân hàng để quét mã.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: CachedNetworkImage(
                    imageUrl: qrUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(color: AppColors.brand),
                    ),
                    errorWidget: (_, _, _) => Image.asset(
                      'assets/images/momo_qr.jpg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                formatVnd(totalPrice, suffix: 'đ'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nội dung: COFFEE $_currentDate',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              MeowPrimaryButton(
                label: 'Xác nhận đã thanh toán',
                height: 48,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _processPayment();
                },
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Hủy bỏ',
                height: 46,
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        ),
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
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'MEOW COFFEE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '83 Hai Bà Trưng, Hoàn Kiếm, TP. Hà Nội\nHotline: 032 8386 66',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.border),
              ),
              Text(
                'Nhân viên: $_userName',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 2),
              Text(
                'Ngày bán: $_currentDate',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              const Text(
                'CHI TIẾT ĐƠN HÀNG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...invoiceItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
                    'Tổng cộng:',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    formatVnd(invoiceTotal, suffix: 'đ'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Phương thức: $_paymentMethod',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              MeowPrimaryButton(
                label: 'Xuất hóa đơn PDF',
                icon: Icons.picture_as_pdf_outlined,
                height: 48,
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
                      SnackBar(content: Text('Đã xuất hóa đơn: ${file.path}')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi xuất PDF: $e')),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Hoàn tất',
                height: 46,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.read<CartProvider>().clearCart();
                  _showCompletionDialog(invoiceTotal);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCompletionDialog(double totalPrice) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: AppColors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Thanh toán thành công',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Đơn hàng đã hoàn tất. Cảm ơn bạn đã ghé Meow Coffee!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                formatVnd(totalPrice, suffix: 'đ'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'Hoàn tất',
                height: 48,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/cart',
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final itemCount = cart.cartItems.fold<int>(0, (s, i) => s + i.quantity);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Hoá Đơn Thanh Toán'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MeowCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.local_cafe_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'MEOW COFFEE',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '83 Hai Bà Trưng, Hoàn Kiếm, TP. Hà Nội',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Hotline: 032 8386 66',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSlate,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                            height: 1,
                            color: AppColors.borderSubtle,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _MetaPill(
                                icon: Icons.person_outline_rounded,
                                label: 'THU NGÂN',
                                value: _userName,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetaPill(
                                icon: Icons.schedule_rounded,
                                label: 'THỜI GIAN',
                                value: _currentDate,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  MeowCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 16,
                                  color: AppColors.brand,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'CHI TIẾT ĐƠN HÀNG',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF475569),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: AppColors.borderSubtle),
                              ),
                              child: Text(
                                '$itemCount sản phẩm',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: AppColors.border),
                        ),
                        ...cart.cartItems.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.soft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.local_cafe_outlined,
                                    size: 18,
                                    color: AppColors.brand,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${item.product.name} ',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.inkSlate,
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'x ${item.quantity}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.brand,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatVnd(item.totalPrice),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brand,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  MeowCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tạm tính:',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              formatVnd(cart.totalPrice),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSlate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Phí dịch vụ:',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              'Miễn phí (0 VNĐ)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                            height: 1,
                            color: AppColors.borderSubtle,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tổng thanh toán',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              formatVnd(cart.totalPrice),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  MeowCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PHƯƠNG THỨC THANH TOÁN',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PaymentMethodTile(
                          title: 'Tiền mặt',
                          subtitle: 'Thanh toán trực tiếp tại quầy',
                          icon: Icons.payments_outlined,
                          selected: _paymentMethod == 'Tiền mặt',
                          onTap: () =>
                              setState(() => _paymentMethod = 'Tiền mặt'),
                        ),
                        const SizedBox(height: 10),
                        _PaymentMethodTile(
                          title: 'Thanh Toán Qua VietQR',
                          subtitle: 'Mở ứng dụng ngân hàng và quét mã QR',
                          icon: Icons.qr_code_2_rounded,
                          selected: _paymentMethod == 'VietQR',
                          onTap: () =>
                              setState(() => _paymentMethod = 'VietQR'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: MeowPrimaryButton(
                  label: 'XÁC NHẬN THANH TOÁN',
                  isLoading: _isLoading,
                  onPressed: () {
                    if (_paymentMethod == 'VietQR') {
                      _showVietQrDialog(cart.totalPrice);
                    } else {
                      _processPayment();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderSubtle.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: AppColors.brand),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedLight,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSlate,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? AppColors.bg : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? AppColors.soft : AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? AppColors.brand : AppColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.brand : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.brand : AppColors.borderSubtle,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Center(
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: Colors.white,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
