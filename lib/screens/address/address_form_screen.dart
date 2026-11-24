import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/address.dart';
import '../../providers/session_provider.dart';
import '../../services/address_service.dart';
import '../../services/vn_admin_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/meow_ui.dart';

/// Thêm / sửa địa chỉ: Tỉnh → Phường/Xã → số nhà, đường → ghim vị trí (bắt buộc).
class AddressFormScreen extends StatefulWidget {
  final Address? existing;

  const AddressFormScreen({super.key, this.existing});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  late AddressLabel _label = widget.existing?.label ?? AddressLabel.home;
  late final _receiverName = TextEditingController();
  late final _receiverPhone = TextEditingController();
  late final _street = TextEditingController(text: widget.existing?.street);
  late final _note = TextEditingController(text: widget.existing?.note);
  Province? _province;
  AdminUnit? _ward;
  late LatLng? _location = widget.existing?.location;
  late bool _makeDefault = widget.existing?.isDefault ?? false;
  List<Province> _provinces = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<SessionProvider>().user;
    _receiverName.text = widget.existing?.receiverName ?? user?.name ?? '';
    _receiverPhone.text = widget.existing?.receiverPhone ?? user?.phone ?? '';
    VnAdminService.provinces().then((list) {
      if (!mounted) return;
      setState(() {
        _provinces = list;
        final e = widget.existing;
        if (e != null) {
          _province = list.where((p) => p.code == e.province.code).firstOrNull;
          _ward = _province?.wards.where((w) => w.code == e.ward.code).firstOrNull;
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_receiverName, _receiverPhone, _street, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickProvince() async {
    final picked = await showUnitPicker<Province>(
      context,
      title: 'Chọn Tỉnh/Thành phố',
      units: _provinces,
      selected: _province,
    );
    if (picked != null && picked != _province) {
      setState(() {
        _province = picked;
        _ward = null; // đổi tỉnh thì chọn lại phường
      });
    }
  }

  Future<void> _pickWard() async {
    final p = _province;
    if (p == null) return;
    final picked = await showUnitPicker<AdminUnit>(
      context,
      title: 'Chọn Phường/Xã',
      units: p.wards,
      selected: _ward,
    );
    if (picked != null) setState(() => _ward = picked);
  }

  Future<void> _pickLocation() async {
    final picked = await pickLocationOnMap(
      context,
      initial: _location,
      title: 'Ghim vị trí giao hàng',
    );
    if (picked != null) setState(() => _location = picked);
  }

  Future<void> _save() async {
    final name = _receiverName.text.trim();
    final phone = toE164Vn(_receiverPhone.text);
    if (name.isEmpty) return _toast('Vui lòng nhập tên người nhận');
    if (phone == null) return _toast('SĐT người nhận không hợp lệ');
    if (_province == null) return _toast('Vui lòng chọn Tỉnh/Thành phố');
    if (_ward == null) return _toast('Vui lòng chọn Phường/Xã');
    if (_street.text.trim().isEmpty) return _toast('Vui lòng nhập số nhà, tên đường');
    if (_location == null) return _toast('Vui lòng ghim vị trí trên bản đồ');

    final address = Address(
      id: widget.existing?.id ?? '',
      label: _label,
      receiverName: name,
      receiverPhone: formatVnPhone(phone),
      province: AdminUnit(_province!.code, _province!.name),
      ward: _ward!,
      street: _street.text.trim(),
      note: _note.text.trim(),
      location: _location!,
      isDefault: widget.existing?.isDefault ?? false,
    );
    final uid = context.read<SessionProvider>().uid;
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await AddressService.add(uid, address, makeDefault: _makeDefault);
      } else {
        await AddressService.update(uid, address, makeDefault: _makeDefault);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e is StateError ? e.message : 'Lỗi lưu địa chỉ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(title: isEdit ? 'Sửa Địa Chỉ' : 'Thêm Địa Chỉ'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _section('LOẠI ĐỊA CHỈ', [
            SegmentedButton<AddressLabel>(
              segments: [
                for (final l in AddressLabel.values)
                  ButtonSegment(value: l, label: Text(l.text)),
              ],
              selected: {_label},
              onSelectionChanged: (s) => setState(() => _label = s.first),
            ),
          ]),
          _section('NGƯỜI NHẬN', [
            _text(_receiverName, 'Tên người nhận'),
            _text(_receiverPhone, 'SĐT người nhận',
                keyboard: TextInputType.phone),
          ]),
          _section('ĐỊA CHỈ', [
            _selector(
              label: 'Tỉnh/Thành phố',
              value: _province?.name,
              enabled: _provinces.isNotEmpty,
              onTap: _pickProvince,
            ),
            _selector(
              label: 'Phường/Xã',
              value: _ward?.name,
              enabled: _province != null,
              hint: _province == null ? 'Chọn Tỉnh/Thành phố trước' : null,
              onTap: _pickWard,
            ),
            _text(_street, 'Số nhà, tên đường', hint: 'Ví dụ: 12 Lê Lợi'),
            _text(_note, 'Ghi chú cho shipper (không bắt buộc)',
                hint: 'Cổng sau, tầng 3, gọi trước khi tới…', lines: 2),
          ]),
          _section('VỊ TRÍ TRÊN BẢN ĐỒ *', [
            if (_location != null) ...[
              MapPreview(location: _location!),
              const SizedBox(height: 10),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Bắt buộc ghim để tính quãng đường và giúp shipper tìm đúng chỗ.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
            MeowSecondaryButton(
              label: _location == null ? 'Ghim vị trí' : 'Ghim lại vị trí',
              icon: Icons.location_on_outlined,
              onPressed: _pickLocation,
            ),
          ]),
          if (!(widget.existing?.isDefault ?? false))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đặt làm địa chỉ mặc định'),
              value: _makeDefault,
              onChanged: (v) => setState(() => _makeDefault = v),
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
              label: 'Lưu địa chỉ',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
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
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _text(
    TextEditingController c,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int lines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          minLines: lines,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _selector({
    required String label,
    required String? value,
    required bool enabled,
    String? hint,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              enabled: enabled,
              suffixIcon: const Icon(Icons.expand_more_rounded),
            ),
            child: Text(
              value ?? hint ?? 'Chọn',
              style: TextStyle(
                color: value == null ? AppColors.mutedLight : AppColors.ink,
              ),
            ),
          ),
        ),
      );
}

/// Bảng chọn có ô tìm kiếm (gõ không dấu vẫn ra).
Future<T?> showUnitPicker<T extends AdminUnit>(
  BuildContext context, {
  required String title,
  required List<T> units,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _UnitPickerSheet<T>(title: title, units: units, selected: selected),
  );
}

class _UnitPickerSheet<T extends AdminUnit> extends StatefulWidget {
  final String title;
  final List<T> units;
  final T? selected;

  const _UnitPickerSheet({required this.title, required this.units, this.selected});

  @override
  State<_UnitPickerSheet<T>> createState() => _UnitPickerSheetState<T>();
}

class _UnitPickerSheetState<T extends AdminUnit> extends State<_UnitPickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = VnAdminService.search(widget.units, _query);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                widget.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Tìm kiếm (gõ không dấu cũng được)',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('Không tìm thấy',
                          style: TextStyle(color: AppColors.muted)),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final u = list[i];
                        final sel = u == widget.selected;
                        return ListTile(
                          title: Text(u.name),
                          trailing: sel
                              ? const Icon(Icons.check_rounded, color: AppColors.brand)
                              : null,
                          onTap: () => Navigator.pop(context, u),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
