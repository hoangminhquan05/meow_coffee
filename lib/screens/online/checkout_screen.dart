import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/address.dart';
import '../../providers/customer_cart_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/address_service.dart';
import '../../services/distance_service.dart';
import '../../services/online_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';
import '../address/address_book_screen.dart';

/// Thanh toán online (bước 5): chọn địa chỉ, xem km/phí/tổng, chọn COD hoặc
/// VietQR, đặt hàng qua Worker. App chỉ ước tính để hiển thị và chặn sớm;
/// Worker kiểm lại toàn bộ (giá, giờ mở cửa, bán kính, đơn tối thiểu).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final Stream<List<Address>> _addresses =
      AddressService.watch(context.read<SessionProvider>().uid);
  final _note = TextEditingController();
  Address? _picked; // null = dùng địa chỉ mặc định
  PaymentMethod _method = PaymentMethod.cash;
  bool _placing = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _changeAddress() async {
    final a = await Navigator.push<Address>(
      context,
      MaterialPageRoute(builder: (_) => const AddressBookScreen(pickMode: true)),
    );
    if (a != null) setState(() => _picked = a);
  }

  Future<void> _place(Address address) async {
    final cart = context.read<CustomerCartProvider>();
    setState(() => _placing = true);
    try {
      final result = await OnlineOrderService.create(
        items: cart.lines,
        addressId: address.id,
        method: _method,
        note: _note.text,
      );
      await cart.clear();
      if (!mounted) return;
      _toast('Đã đặt đơn ${result.orderCode}');
      Navigator.pushReplacementNamed(context, '/my_order', arguments: result.orderId);
    } on OnlineOrderError catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CustomerCartProvider>();
    final shop = context.watch<ShopSettingsProvider>().settings;
    final user = context.watch<SessionProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Thanh Toán'),
      body: StreamBuilder<List<Address>>(
        stream: _addresses,
        builder: (context, snap) {
          final list = snap.data ?? const <Address>[];
          // Địa chỉ đã chọn còn trong sổ thì giữ, không thì dùng mặc định.
          final address = (_picked != null && list.any((a) => a.id == _picked!.id))
              ? list.firstWhere((a) => a.id == _picked!.id)
              : (list.isEmpty ? null : list.first);
          final from = shop.location;

          return FutureBuilder<DistanceResult?>(
            future: (address == null || from == null)
                ? Future.value(null)
                : DistanceService.road(from, address.location),
            initialData: (address == null || from == null)
                ? null
                : DistanceService.cached(from, address.location),
            builder: (context, dSnap) {
              final distance = dSnap.data;
              final fee = distance == null ? 0 : shop.shippingFee.feeFor(distance.km);
              final total = cart.subtotal + fee;

              // Lý do chặn đặt hàng (theo thứ tự ưu tiên).
              String? blocker = shop.closedReason(DateTime.now());
              VoidCallback? fix;
              String? fixLabel;
              if (blocker == null && !(user?.isVerified ?? false)) {
                blocker = 'Vui lòng xác minh số điện thoại hoặc email trước khi đặt đơn';
                fix = () => Navigator.pushNamed(context, '/verify_account');
                fixLabel = 'Xác minh ngay';
              }
              if (blocker == null && !cart.allOrderable) {
                blocker = cart.isEmpty
                    ? 'Giỏ hàng trống'
                    : 'Có món không còn bán, quay lại giỏ để bỏ món đó';
              }
              if (blocker == null && address == null && snap.hasData) {
                blocker = 'Vui lòng thêm địa chỉ giao hàng';
                fix = _changeAddress;
                fixLabel = 'Thêm địa chỉ';
              }
              if (blocker == null && shop.minOrderValue > 0 &&
                  cart.subtotal < shop.minOrderValue) {
                blocker =
                    'Mua thêm ${formatMoney(shop.minOrderValue - cart.subtotal)} để được giao hàng';
              }
              if (blocker == null && distance != null && distance.km > shop.maxDeliveryKm) {
                blocker = 'Địa chỉ cách quán ${distance.label}, quán chỉ giao trong '
                    '${_km(shop.maxDeliveryKm)} km';
              }
              final calculating = address != null && from != null && distance == null;

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        _AddressCard(
                          address: address,
                          distance: distance,
                          loading: !snap.hasData,
                          onChange: _changeAddress,
                        ),
                        const SizedBox(height: 12),
                        _ItemsCard(cart: cart),
                        const SizedBox(height: 12),
                        _PaymentCard(
                          method: _method,
                          onChanged: (m) => setState(() => _method = m),
                          timeoutMin: shop.paymentTimeoutMin,
                        ),
                        const SizedBox(height: 12),
                        MeowCard(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _note,
                            maxLength: 200,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Ghi chú cho quán (không bắt buộc)',
                              hintText: 'Ví dụ: gọi trước khi tới',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SummaryCard(
                          subtotal: cart.subtotal,
                          fee: fee,
                          feeEnabled: shop.shippingFee.enabled,
                          total: total,
                        ),
                      ],
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
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (blocker != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        size: 18, color: AppColors.danger),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(blocker,
                                          style: const TextStyle(
                                              fontSize: 12.5, color: AppColors.danger)),
                                    ),
                                    if (fix != null)
                                      TextButton(onPressed: fix, child: Text(fixLabel!)),
                                  ],
                                ),
                              ),
                            MeowPrimaryButton(
                              label: calculating
                                  ? 'ĐANG TÍNH QUÃNG ĐƯỜNG…'
                                  : 'ĐẶT HÀNG • ${formatMoney(total)}',
                              isLoading: _placing,
                              onPressed: (blocker == null && !calculating && !_placing)
                                  ? () => _place(address!)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _km(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

const _title = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Color(0xFF475569),
  letterSpacing: 0.5,
);

class _AddressCard extends StatelessWidget {
  final Address? address;
  final DistanceResult? distance;
  final bool loading;
  final VoidCallback onChange;

  const _AddressCard({
    required this.address,
    required this.distance,
    required this.loading,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final a = address;
    return MeowCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('GIAO ĐẾN', style: _title)),
              TextButton(onPressed: onChange, child: Text(a == null ? 'Thêm' : 'Đổi')),
            ],
          ),
          if (loading)
            const LinearProgressIndicator(color: AppColors.brand)
          else if (a == null)
            const Text('Chưa có địa chỉ giao hàng',
                style: TextStyle(color: AppColors.danger))
          else ...[
            Text('${a.label.text} · ${a.receiverName} · ${a.receiverPhone}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(a.fullText, style: const TextStyle(color: AppColors.muted)),
            if (a.note.isNotEmpty)
              Text('Ghi chú: ${a.note}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(
              distance == null ? 'Đang tính quãng đường…' : 'Cách quán ${distance!.label}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.success),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final CustomerCartProvider cart;

  const _ItemsCard({required this.cart});

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('MÓN (${cart.totalItems})', style: _title),
          const SizedBox(height: 8),
          for (final l in cart.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l.displayName} × ${l.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (l.note.isNotEmpty)
                          Text(l.note,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(formatMoney(l.lineTotal)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentMethod method;
  final ValueChanged<PaymentMethod> onChanged;
  final int timeoutMin;

  const _PaymentCard({
    required this.method,
    required this.onChanged,
    required this.timeoutMin,
  });

  @override
  Widget build(BuildContext context) {
    Widget tile(PaymentMethod m, String title, String sub, IconData icon) {
      final selected = method == m;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(m),
          child: Container(
            padding: const EdgeInsets.all(12),
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
                Icon(icon, color: selected ? AppColors.brand : AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(sub,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.brand : AppColors.borderSubtle,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('THANH TOÁN', style: _title),
          tile(PaymentMethod.cash, 'Tiền mặt khi nhận hàng (COD)',
              'Trả cho shipper khi nhận món', Icons.payments_outlined),
          tile(PaymentMethod.vietqr, 'Chuyển khoản VietQR',
              'Quét mã QR trong $timeoutMin phút sau khi đặt', Icons.qr_code_2_rounded),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int subtotal;
  final int fee;
  final bool feeEnabled;
  final int total;

  const _SummaryCard({
    required this.subtotal,
    required this.fee,
    required this.feeEnabled,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                        fontSize: bold ? 15 : 13.5)),
              ),
              Text(v,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 18 : 13.5,
                      color: bold ? AppColors.brand : AppColors.ink)),
            ],
          ),
        );
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          row('Tạm tính', formatMoney(subtotal)),
          row('Phí giao hàng', feeEnabled ? formatMoney(fee) : 'Miễn phí'),
          const Divider(),
          row('Tổng thanh toán', formatMoney(total), bold: true),
        ],
      ),
    );
  }
}
