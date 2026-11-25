import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/shop_settings.dart';
import '../../providers/session_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/meow_ui.dart';

/// Cài đặt quán (admin) – bước 1 kế hoạch bán online.
/// Bấm "Lưu cài đặt" mới ghi; riêng công tắc Tạm ngưng có hiệu lực ngay.
class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;

  // Thông tin quán
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  LatLng? _location;

  // Nhận đơn online
  String _openTime = '07:00';
  String _closeTime = '22:00';
  final _maxKm = TextEditingController();
  final _minOrder = TextEditingController();

  bool _requireShipper = false;

  // Phí ship
  bool _feeEnabled = false;
  final _baseKm = TextEditingController();
  final _baseFee = TextEditingController();
  final _perKm = TextEditingController();

  // Thanh toán, giao hàng
  final _paymentTimeout = TextEditingController();
  final _failWait = TextEditingController();
  final _failCalls = TextEditingController();

  // Nâng cao (gán shipper)
  final _offerSeconds = TextEditingController();
  final _maxOrders = TextEditingController();
  final _batchRadius = TextEditingController();
  final _staleMin = TextEditingController();
  final _wLoad = TextEditingController();
  final _wPickup = TextEditingController();
  final _wDetour = TextEditingController();
  final _wToday = TextEditingController();

  List<TextEditingController> get _all => [
        _name, _address, _phone, _maxKm, _minOrder, _baseKm, _baseFee, _perKm,
        _paymentTimeout, _failWait, _failCalls, _offerSeconds, _maxOrders,
        _batchRadius, _staleMin, _wLoad, _wPickup, _wDetour, _wToday,
      ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  void _fill(ShopSettings s) {
    _name.text = s.name;
    _address.text = s.address;
    _phone.text = s.phone;
    _location = s.location;
    _openTime = s.openTime;
    _closeTime = s.closeTime;
    _maxKm.text = _num(s.maxDeliveryKm);
    _minOrder.text = _num(s.minOrderValue);
    _requireShipper = s.requireShipperOnShift;
    _feeEnabled = s.shippingFee.enabled;
    _baseKm.text = _num(s.shippingFee.baseKm);
    _baseFee.text = _num(s.shippingFee.baseFee);
    _perKm.text = _num(s.shippingFee.perKm);
    _paymentTimeout.text = _num(s.paymentTimeoutMin);
    _failWait.text = _num(s.deliveryFailure.waitMinutes);
    _failCalls.text = _num(s.deliveryFailure.minCallAttempts);
    _fillAdvanced(s.dispatch);
  }

  void _fillAdvanced(DispatchConfig d) {
    _offerSeconds.text = _num(d.offerSeconds);
    _maxOrders.text = _num(d.maxOrdersPerShipper);
    _batchRadius.text = _num(d.batchRadiusKm);
    _staleMin.text = _num(d.staleLocationMin);
    _wLoad.text = _num(d.weights.load);
    _wPickup.text = _num(d.weights.pickupKm);
    _wDetour.text = _num(d.weights.detourKm);
    _wToday.text = _num(d.weights.today);
  }

  /// Luôn setState để phần "Ví dụ phí" cập nhật theo số đang gõ.
  void _markDirty() => setState(() => _dirty = true);

  /// Đọc form → ShopSettings; trả về lỗi (tiếng Việt) nếu không hợp lệ.
  (ShopSettings?, String?) _build(bool onlinePaused) {
    int? i(TextEditingController c, {int min = 0}) {
      final v = int.tryParse(c.text.trim().replaceAll('.', ''));
      return (v != null && v >= min) ? v : null;
    }

    double? d(TextEditingController c, {double min = 0}) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      return (v != null && v >= min) ? v : null;
    }

    if (_name.text.trim().isEmpty) return (null, 'Vui lòng nhập tên quán');
    final maxKm = d(_maxKm, min: 0.1);
    final minOrder = i(_minOrder);
    final baseKm = d(_baseKm);
    final baseFee = i(_baseFee);
    final perKm = i(_perKm);
    final payTimeout = i(_paymentTimeout, min: 1);
    final failWait = i(_failWait);
    final failCalls = i(_failCalls);
    final offer = i(_offerSeconds, min: 10);
    final maxOrders = i(_maxOrders, min: 1);
    final batch = d(_batchRadius);
    final stale = i(_staleMin, min: 1);
    final wl = d(_wLoad), wp = d(_wPickup), wd = d(_wDetour), wt = d(_wToday);

    if (maxKm == null) return (null, 'Bán kính giao phải lớn hơn 0');
    if (minOrder == null) return (null, 'Giá trị đơn tối thiểu không hợp lệ');
    if (baseKm == null || baseFee == null || perKm == null) {
      return (null, 'Thông số phí giao hàng không hợp lệ');
    }
    if (payTimeout == null) return (null, 'Thời hạn thanh toán ít nhất 1 phút');
    if (failWait == null || failCalls == null) {
      return (null, 'Điều kiện giao thất bại không hợp lệ');
    }
    if (offer == null || maxOrders == null || batch == null || stale == null ||
        wl == null || wp == null || wd == null || wt == null) {
      return (null, 'Thông số gán shipper (Nâng cao) không hợp lệ');
    }

    return (
      ShopSettings(
        name: _name.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        location: _location,
        openTime: _openTime,
        closeTime: _closeTime,
        onlinePaused: onlinePaused,
        maxDeliveryKm: maxKm,
        minOrderValue: minOrder,
        shippingFee: ShippingFeeConfig(
          enabled: _feeEnabled,
          baseKm: baseKm,
          baseFee: baseFee,
          perKm: perKm,
        ),
        paymentTimeoutMin: payTimeout,
        requireShipperOnShift: _requireShipper,
        deliveryFailure:
            DeliveryFailureConfig(waitMinutes: failWait, minCallAttempts: failCalls),
        dispatch: DispatchConfig(
          offerSeconds: offer,
          maxOrdersPerShipper: maxOrders,
          batchRadiusKm: batch,
          staleLocationMin: stale,
          weights: DispatchWeights(
            load: wl,
            pickupKm: wp,
            detourKm: wd,
            today: wt,
          ),
        ),
      ),
      null,
    );
  }

  Future<void> _save() async {
    final current = context.read<ShopSettingsProvider>().settings;
    final (settings, error) = _build(current.onlinePaused);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      await ShopSettingsProvider.save(
        settings!,
        context.read<SessionProvider>().personRef,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cài đặt quán')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi lưu cài đặt: $e')));
    }
  }

  Future<void> _togglePaused(bool value) async {
    try {
      await ShopSettingsProvider.setOnlinePaused(
        value,
        context.read<SessionProvider>().personRef,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Đã tạm ngưng nhận đơn online'
            : 'Đã mở lại nhận đơn online'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _pickTime(bool isOpen) async {
    final parts = (isOpen ? _openTime : _closeTime).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 7,
        minute: int.tryParse(parts[1]) ?? 0,
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isOpen) {
        _openTime = v;
      } else {
        _closeTime = v;
      }
      _dirty = true;
    });
  }

  Future<void> _pickLocation() async {
    final picked = await pickLocationOnMap(
      context,
      initial: _location,
      title: 'Ghim vị trí quán',
    );
    if (picked != null) {
      setState(() {
        _location = picked;
        _dirty = true;
      });
    }
  }

  Future<bool> _confirmDiscard() => showMeowConfirmDialog(
        context,
        title: 'Chưa lưu thay đổi',
        message: 'Bạn có muốn bỏ các thay đổi chưa lưu?',
        confirmLabel: 'Bỏ thay đổi',
        cancelLabel: 'Ở lại',
      );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShopSettingsProvider>();
    if (!provider.isLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        appBar: MeowHeader(title: 'Cài Đặt Quán'),
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    if (!_initialized) {
      _fill(provider.settings);
      _initialized = true;
    }
    final paused = provider.settings.onlinePaused;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: const MeowHeader(title: 'Cài Đặt Quán'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (provider.error != null)
              _Banner(
                color: AppColors.danger,
                text: 'Không tải được cài đặt: ${provider.error}',
              ),
            if (!provider.exists)
              const _Banner(
                color: AppColors.warning,
                text: 'Chưa có cài đặt trên hệ thống – đang hiện giá trị mặc định. '
                    'Bấm "Lưu cài đặt" để tạo.',
              ),
            if (_location == null)
              const _Banner(
                color: AppColors.danger,
                text: 'Chưa ghim vị trí quán – khách chưa đặt được đơn online.',
              ),
            _Section(
              title: 'THÔNG TIN QUÁN',
              subtitle: 'In trên hóa đơn và hiện cho khách',
              children: [
                _field('Tên quán *', _name),
                _field('Địa chỉ', _address),
                _field('Hotline', _phone, keyboard: TextInputType.phone),
              ],
            ),
            _Section(
              title: 'VỊ TRÍ QUÁN',
              subtitle: 'Điểm bắt đầu tính quãng đường giao hàng',
              children: [
                if (_location != null) ...[
                  MapPreview(location: _location!),
                  const SizedBox(height: 10),
                ],
                MeowSecondaryButton(
                  label: _location == null ? 'Ghim vị trí quán' : 'Đổi vị trí',
                  icon: Icons.location_on_outlined,
                  onPressed: _pickLocation,
                ),
              ],
            ),
            _Section(
              title: 'NHẬN ĐƠN ONLINE',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tạm ngưng nhận đơn online',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    paused
                        ? 'Đang tạm ngưng – khách chỉ xem được thực đơn'
                        : 'Có hiệu lực ngay, không cần bấm Lưu',
                    style: TextStyle(
                      fontSize: 12,
                      color: paused ? AppColors.danger : AppColors.muted,
                    ),
                  ),
                  value: paused,
                  activeThumbColor: AppColors.danger,
                  onChanged: _togglePaused,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _TimeTile(
                        label: 'Mở nhận đơn',
                        value: _openTime,
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeTile(
                        label: 'Ngừng nhận đơn',
                        value: _closeTime,
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Áp dụng mọi ngày; giờ ngừng nhỏ hơn giờ mở nghĩa là qua nửa đêm.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ),
                _field('Bán kính giao tối đa (km)', _maxKm,
                    keyboard: const TextInputType.numberWithOptions(decimal: true)),
                _field('Giá trị đơn tối thiểu (VNĐ, 0 = tắt)', _minOrder,
                    keyboard: TextInputType.number),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yêu cầu có shipper trong ca',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                    'Bật thì chặn đặt đơn khi không có shipper nào đang trong ca '
                    '(nên bật khi quán vào ca có đủ người bán và shipper).',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  value: _requireShipper,
                  onChanged: (v) => setState(() {
                    _requireShipper = v;
                    _dirty = true;
                  }),
                ),
              ],
            ),
            _Section(
              title: 'PHÍ GIAO HÀNG',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tính phí giao hàng',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                    'Tắt = miễn phí giao (giai đoạn 1)',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  value: _feeEnabled,
                  onChanged: (v) => setState(() {
                    _feeEnabled = v;
                    _dirty = true;
                  }),
                ),
                Row(
                  children: [
                    Expanded(
                        child: _field('Số km đầu', _baseKm,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field('Giá km đầu (VNĐ)', _baseFee,
                            keyboard: TextInputType.number)),
                  ],
                ),
                _field('Mỗi km tiếp theo (VNĐ)', _perKm,
                    keyboard: TextInputType.number),
                _FeeExample(
                  baseKm: _baseKm.text,
                  baseFee: _baseFee.text,
                  perKm: _perKm.text,
                  enabled: _feeEnabled,
                ),
              ],
            ),
            _Section(
              title: 'THANH TOÁN & GIAO HÀNG',
              children: [
                _field('Thời hạn chuyển khoản VietQR (phút)', _paymentTimeout,
                    keyboard: TextInputType.number),
                Row(
                  children: [
                    Expanded(
                        child: _field('Chờ trước khi báo thất bại (phút)',
                            _failWait,
                            keyboard: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field('Số lần gọi tối thiểu', _failCalls,
                            keyboard: TextInputType.number)),
                  ],
                ),
              ],
            ),
            Card(
              elevation: 0,
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ExpansionTile(
                shape: const Border(),
                title: const Text('Nâng cao: gán shipper',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'Chỉ chỉnh khi hiểu rõ thuật toán',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Row(children: [
                    Expanded(
                        child: _field('Thời gian mời (giây)', _offerSeconds,
                            keyboard: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field('Tối đa đơn/shipper', _maxOrders,
                            keyboard: TextInputType.number)),
                  ]),
                  Row(children: [
                    Expanded(
                        child: _field('Bán kính ghép đơn (km)', _batchRadius,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field('Bỏ qua GPS cũ hơn (phút)', _staleMin,
                            keyboard: TextInputType.number)),
                  ]),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Trọng số điểm (điểm càng nhỏ càng được ưu tiên)',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  Row(children: [
                    Expanded(child: _field('Số đơn đang giữ', _wLoad, decimal: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('Km shipper → quán', _wPickup, decimal: true)),
                  ]),
                  Row(children: [
                    Expanded(child: _field('Km phát sinh khi ghép', _wDetour, decimal: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('Đơn đã giao hôm nay', _wToday, decimal: true)),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Khôi phục mặc định'),
                      onPressed: () => setState(() {
                        _fillAdvanced(const DispatchConfig());
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
              ),
            ),
            if (provider.settings.updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Cập nhật lần cuối: ${formatDateTime(provider.settings.updatedAt)}'
                  '${provider.settings.updatedByName != null ? ' bởi ${provider.settings.updatedByName}' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: MeowPrimaryButton(
                label: _dirty ? 'Lưu cài đặt' : 'Đã lưu',
                icon: Icons.save_outlined,
                isLoading: _saving,
                onPressed: _dirty && !_saving ? _save : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : keyboard,
        onChanged: (_) => _markDirty(),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: AppColors.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MeowCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
                letterSpacing: 0.5,
              ),
            ),
            if (subtitle != null)
              Text(subtitle!,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final String text;

  const _Banner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: color)),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.brand),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ví dụ phí cho 2 / 5 / 8 km theo các số đang nhập.
class _FeeExample extends StatelessWidget {
  final String baseKm;
  final String baseFee;
  final String perKm;
  final bool enabled;

  const _FeeExample({
    required this.baseKm,
    required this.baseFee,
    required this.perKm,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = ShippingFeeConfig(
      enabled: true,
      baseKm: double.tryParse(baseKm.replaceAll(',', '.')) ?? 0,
      baseFee: int.tryParse(baseFee) ?? 0,
      perKm: int.tryParse(perKm) ?? 0,
    );
    final sample = [2.0, 5.0, 8.0]
        .map((km) => '${km.toStringAsFixed(0)} km: ${formatMoney(cfg.feeFor(km))}')
        .join(' · ');
    return Text(
      enabled ? 'Ví dụ: $sample' : 'Đang tắt – mọi đơn phí 0đ. (Khi bật: $sample)',
      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
    );
  }
}
