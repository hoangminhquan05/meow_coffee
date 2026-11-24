import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/order.dart';
import '../../models/table_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/order_service.dart';
import '../../services/table_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/vietqr.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/order_receipt.dart';

/// Thanh toán bán tại quán (L3 → L7).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final TextEditingController _noteController =
      TextEditingController(text: context.read<CartProvider>().orderNote);
  late final Stream<List<TableModel>> _tablesStream = TableService.watchAll();
  PaymentMethod _method = PaymentMethod.cash;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- VietQR

  /// Nội dung chuyển khoản, lưu vào đơn để đối soát (L5).
  String _newPaymentRef() =>
      'MEOW${DateFormat('ddMMyyHHmmss').format(DateTime.now())}';

  String _buildVietQrUrl(int amount, String ref) =>
      buildVietQrUrl(amount: amount, content: ref);

  // ---------------------------------------------------------------- Flow

  Future<void> _onConfirmPressed() async {
    final cart = context.read<CartProvider>();
    if (!cart.isReadyToPay || _isSubmitting) return;
    final total = cart.total;

    if (_method == PaymentMethod.cash) {
      final ok = await _showCashDialog(total);
      if (ok) await _createOrder(PaymentMethod.cash, null);
    } else {
      final ref = _newPaymentRef();
      final ok = await _showVietQrDialog(total, ref);
      if (ok) await _createOrder(PaymentMethod.vietqr, ref);
    }
  }

  Future<void> _createOrder(PaymentMethod method, String? ref) async {
    final cart = context.read<CartProvider>();
    final session = context.read<SessionProvider>();
    cart.setOrderNote(_noteController.text);
    setState(() => _isSubmitting = true);
    try {
      final order = await OrderService.createInStoreOrder(
        cart: cart,
        method: method,
        seller: session.personRef,
        paymentRef: ref,
      );
      if (!mounted) return;
      // Đơn đã lưu → mới xóa giỏ (L6).
      cart.clear();
      setState(() => _isSubmitting = false);
      await _showInvoiceDialog(order);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // Lỗi → giữ nguyên giỏ, không tạo đơn.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tạo được đơn, vui lòng thử lại. ($e)')),
      );
    }
  }

  // ---------------------------------------------------------------- Dialogs

  Future<bool> _showCashDialog(int total) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.payments_outlined,
                  size: 40, color: AppColors.brand),
              const SizedBox(height: 10),
              const Text(
                'Thu tiền mặt',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              // Q10: chỉ hiện số tiền phải thu.
              Text(
                'Thu: ${formatMoney(total)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'Đã nhận tiền',
                height: 48,
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Quay lại',
                height: 46,
                onPressed: () => Navigator.pop(dialogContext, false),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<bool> _showVietQrDialog(int total, String ref) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VietQrDialog(
        qrUrl: _buildVietQrUrl(total, ref),
        total: total,
        paymentRef: ref,
      ),
    );
    return result ?? false;
  }

  Future<void> _showInvoiceDialog(Order order) async {
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
              OrderReceiptView(order: order),
              const SizedBox(height: 18),
              MeowPrimaryButton(
                label: 'Xuất hóa đơn PDF',
                icon: Icons.picture_as_pdf_outlined,
                height: 48,
                onPressed: () => exportInvoicePdf(context, order),
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Đơn mới',
                height: 46,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
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

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final session = context.watch<SessionProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Thanh Toán'),
      body: cart.isEmpty
          ? const Center(
              child: Text(
                'Giỏ hàng trống',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildItemsCard(cart),
                        const SizedBox(height: 14),
                        _buildOrderInfoCard(cart),
                        const SizedBox(height: 14),
                        _buildPaymentMethodCard(),
                        const SizedBox(height: 10),
                        Text(
                          'Thu ngân: ${session.user?.name ?? ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(cart),
              ],
            ),
    );
  }

  static const _sectionTitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Color(0xFF475569),
    letterSpacing: 0.5,
  );

  Widget _buildItemsCard(CartProvider cart) {
    return MeowCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CHI TIẾT ĐƠN HÀNG', style: _sectionTitle),
              Text(
                '${cart.totalItems} món',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.border),
          ),
          for (final item in cart.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkSlate,
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
                  Text(
                    formatMoney(item.lineTotal),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderInfoCard(CartProvider cart) {
    final isDineIn = cart.fulfillment == Fulfillment.dineIn;
    return MeowCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('LOẠI ĐƠN', style: _sectionTitle),
          const SizedBox(height: 10),
          SegmentedButton<Fulfillment>(
            segments: const [
              ButtonSegment(
                value: Fulfillment.dineIn,
                label: Text('Tại quán'),
                icon: Icon(Icons.table_restaurant_outlined),
              ),
              ButtonSegment(
                value: Fulfillment.takeaway,
                label: Text('Mang đi'),
                icon: Icon(Icons.takeout_dining_outlined),
              ),
            ],
            selected: {cart.fulfillment},
            onSelectionChanged: (s) => cart.setFulfillment(s.first),
          ),
          if (isDineIn) ...[
            const SizedBox(height: 16),
            const Text('SỐ BÀN *', style: _sectionTitle),
            const SizedBox(height: 8),
            StreamBuilder<List<TableModel>>(
              stream: _tablesStream,
              builder: (context, snapshot) {
                final tables = snapshot.data ?? const <TableModel>[];
                if (snapshot.hasError) {
                  return Text('Lỗi tải bàn: ${snapshot.error}',
                      style: const TextStyle(color: AppColors.danger));
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator(color: AppColors.brand);
                }
                if (tables.isEmpty) {
                  return const Text(
                    'Chưa có bàn nào, nhờ quản lý thêm bàn.',
                    style: TextStyle(color: AppColors.danger),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tables)
                      ChoiceChip(
                        label: Text('Bàn ${t.tableNumber}'),
                        selected: cart.tableNumber == t.tableNumber,
                        onSelected: (_) => cart.setTableNumber(t.tableNumber),
                        selectedColor: AppColors.soft,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cart.tableNumber == t.tableNumber
                              ? AppColors.brand
                              : AppColors.ink,
                        ),
                      ),
                  ],
                );
              },
            ),
            if (cart.tableNumber == null) ...[
              const SizedBox(height: 6),
              const Text(
                'Vui lòng chọn bàn',
                style: TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ],
          ],
          const SizedBox(height: 16),
          const Text('GHI CHÚ ĐƠN', style: _sectionTitle),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            onChanged: cart.setOrderNote,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Ví dụ: khách chờ ở cửa',
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    return MeowCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PHƯƠNG THỨC THANH TOÁN', style: _sectionTitle),
          const SizedBox(height: 10),
          _PaymentMethodTile(
            title: 'Tiền mặt',
            subtitle: 'Thu trực tiếp tại quầy',
            icon: Icons.payments_outlined,
            selected: _method == PaymentMethod.cash,
            onTap: () => setState(() => _method = PaymentMethod.cash),
          ),
          const SizedBox(height: 10),
          _PaymentMethodTile(
            title: 'Chuyển khoản VietQR',
            subtitle: 'Khách quét mã QR bằng app ngân hàng',
            icon: Icons.qr_code_2_rounded,
            selected: _method == PaymentMethod.vietqr,
            onTap: () => setState(() => _method = PaymentMethod.vietqr),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(CartProvider cart) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    formatMoney(cart.total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MeowPrimaryButton(
                label: cart.isReadyToPay
                    ? 'XÁC NHẬN THANH TOÁN'
                    : 'CHỌN BÀN ĐỂ THANH TOÁN',
                isLoading: _isSubmitting,
                onPressed: cart.isReadyToPay && !_isSubmitting
                    ? _onConfirmPressed
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Xuất PDF và báo kết quả.
Future<void> exportInvoicePdf(BuildContext context, Order order) async {
  try {
    final file = await InvoicePdfService.generateAndSave(
      order,
      context.read<ShopSettingsProvider>().settings,
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
}

/// Dialog VietQR (L5). Ảnh QR lỗi → báo lỗi + "Thử lại", không dùng ảnh tĩnh.
class _VietQrDialog extends StatefulWidget {
  final String qrUrl;
  final int total;
  final String paymentRef;

  const _VietQrDialog({
    required this.qrUrl,
    required this.total,
    required this.paymentRef,
  });

  @override
  State<_VietQrDialog> createState() => _VietQrDialogState();
}

class _VietQrDialogState extends State<_VietQrDialog> {
  int _attempt = 0;
  bool _qrLoaded = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
              'Khách mở ứng dụng ngân hàng để quét mã.',
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
                  key: ValueKey(_attempt),
                  imageUrl: widget.qrUrl,
                  fit: BoxFit.contain,
                  imageBuilder: (context, provider) {
                    if (!_qrLoaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _qrLoaded = true);
                      });
                    }
                    return Image(image: provider, fit: BoxFit.contain);
                  },
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  ),
                  errorWidget: (_, _, _) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 40, color: AppColors.danger),
                      const SizedBox(height: 8),
                      const Text(
                        'Không tải được mã QR',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      TextButton(
                        onPressed: () async {
                          await CachedNetworkImage.evictFromCache(widget.qrUrl);
                          setState(() => _attempt++);
                        },
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              formatMoney(widget.total),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nội dung: ${widget.paymentRef}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            const Text(
              'Kiểm tra app ngân hàng của quán thấy tiền về đúng số tiền rồi mới bấm "Đã nhận tiền".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.mutedLight),
            ),
            const SizedBox(height: 18),
            MeowPrimaryButton(
              label: 'Đã nhận tiền',
              height: 48,
              onPressed:
                  _qrLoaded ? () => Navigator.pop(context, true) : null,
            ),
            const SizedBox(height: 10),
            MeowSecondaryButton(
              label: 'Hủy',
              height: 46,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
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
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.brand : AppColors.borderSubtle,
            ),
          ],
        ),
      ),
    );
  }
}
