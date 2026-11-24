import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/address.dart';
import '../../models/shop_settings.dart';
import '../../providers/session_provider.dart';
import '../../providers/shop_settings_provider.dart';
import '../../services/address_service.dart';
import '../../services/distance_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';
import 'address_form_screen.dart';

/// Sổ địa chỉ của khách (tối đa 3). `pickMode = true` → chạm để chọn và trả về
/// địa chỉ (dùng ở màn thanh toán online, bước 5).
class AddressBookScreen extends StatefulWidget {
  final bool pickMode;

  const AddressBookScreen({super.key, this.pickMode = false});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  late final Stream<List<Address>> _stream =
      AddressService.watch(context.read<SessionProvider>().uid);

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openForm([Address? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddressFormScreen(existing: existing)),
    );
    if (saved == true && mounted) {
      _toast(existing == null ? 'Đã thêm địa chỉ' : 'Đã cập nhật địa chỉ');
    }
  }

  Future<void> _delete(Address a) async {
    final ok = await showMeowConfirmDialog(
      context,
      title: 'Xóa địa chỉ',
      message: 'Xóa địa chỉ "${a.label.text}" – ${a.fullText}?',
      confirmLabel: 'Xóa',
    );
    if (!ok || !mounted) return;
    try {
      await AddressService.delete(context.read<SessionProvider>().uid, a);
      _toast('Đã xóa địa chỉ');
    } catch (e) {
      _toast('Lỗi xóa địa chỉ: $e');
    }
  }

  Future<void> _setDefault(Address a) async {
    try {
      await AddressService.setDefault(context.read<SessionProvider>().uid, a.id);
      _toast('Đã đặt "${a.label.text}" làm mặc định');
    } catch (e) {
      _toast('Lỗi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopSettingsProvider>().settings;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: widget.pickMode ? 'Chọn Địa Chỉ Giao' : 'Sổ Địa Chỉ',
      ),
      body: StreamBuilder<List<Address>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Lỗi tải địa chỉ: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.danger)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.brand));
          }
          final list = snapshot.data!;
          final full = list.length >= Address.maxPerUser;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.location_off_outlined,
                          size: 48, color: AppColors.mutedLight),
                      SizedBox(height: 10),
                      Text('Chưa có địa chỉ nào',
                          style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              for (final a in list) ...[
                _AddressCard(
                  address: a,
                  shop: shop,
                  onTap: widget.pickMode
                      ? () => Navigator.pop(context, a)
                      : () => _openForm(a),
                  onEdit: () => _openForm(a),
                  onDelete: () => _delete(a),
                  onSetDefault: a.isDefault ? null : () => _setDefault(a),
                ),
                const SizedBox(height: 12),
              ],
              MeowSecondaryButton(
                label: full
                    ? 'Đã đủ ${Address.maxPerUser} địa chỉ'
                    : 'Thêm địa chỉ mới',
                icon: Icons.add_location_alt_outlined,
                onPressed: full ? null : () => _openForm(),
              ),
              if (full)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Xóa bớt một địa chỉ để thêm địa chỉ mới.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final Address address;
  final ShopSettings shop;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;

  const _AddressCard({
    required this.address,
    required this.shop,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final a = address;
    return MeowCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
      borderColor: a.isDefault ? AppColors.brand : AppColors.border,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              switch (a.label) {
                AddressLabel.home => Icons.home_outlined,
                AddressLabel.work => Icons.business_outlined,
                AddressLabel.other => Icons.place_outlined,
              },
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(a.label.text,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    if (a.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.soft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Mặc định',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('${a.receiverName} · ${a.receiverPhone}',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSlate)),
                Text(a.fullText,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                if (a.note.isNotEmpty)
                  Text('Ghi chú: ${a.note}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.muted)),
                const SizedBox(height: 4),
                _DistanceLine(address: a, shop: shop),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
              if (v == 'default') onSetDefault?.call();
            },
            itemBuilder: (_) => [
              if (onSetDefault != null)
                const PopupMenuItem(value: 'default', child: Text('Đặt làm mặc định')),
              const PopupMenuItem(value: 'edit', child: Text('Sửa')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Xóa', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Cách quán 3,2 km" hoặc "Ngoài vùng giao" (O10).
class _DistanceLine extends StatelessWidget {
  final Address address;
  final ShopSettings shop;

  const _DistanceLine({required this.address, required this.shop});

  @override
  Widget build(BuildContext context) {
    final from = shop.location;
    if (from == null) return const SizedBox.shrink();
    return FutureBuilder<DistanceResult>(
      initialData: DistanceService.cached(from, address.location),
      future: DistanceService.road(from, address.location),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Text('Đang tính quãng đường…',
              style: TextStyle(fontSize: 12, color: AppColors.mutedLight));
        }
        final d = snap.data!;
        final outside = d.km > shop.maxDeliveryKm;
        final maxKm = shop.maxDeliveryKm.toStringAsFixed(
            shop.maxDeliveryKm == shop.maxDeliveryKm.roundToDouble() ? 0 : 1);
        return Text(
          outside
              ? 'Ngoài vùng giao: cách quán ${d.label} (quán giao trong $maxKm km)'
              : 'Cách quán ${d.label}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: outside ? AppColors.danger : AppColors.success,
          ),
        );
      },
    );
  }
}
