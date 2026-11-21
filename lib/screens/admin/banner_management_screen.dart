import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/banner_model.dart';
import '../../providers/banner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

class BannerManagementScreen extends StatefulWidget {
  const BannerManagementScreen({super.key});

  @override
  State<BannerManagementScreen> createState() => _BannerManagementScreenState();
}

class _BannerManagementScreenState extends State<BannerManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BannerProvider>().loadBanners();
    });
  }

  Future<void> _openBannerDialog({BannerModel? existing}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BannerDialog(existing: existing),
    );
  }

  Future<void> _confirmDeleteBanner(BannerModel banner) async {
    final confirmed = await showMeowConfirmDialog(
      context,
      title: 'Xóa banner',
      message: 'Xóa banner “${banner.name}”?',
      confirmLabel: 'Xóa banner',
      cancelLabel: 'Hủy',
      isDanger: true,
    );
    if (confirmed && mounted) {
      await context.read<BannerProvider>().deleteBanner(banner.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BannerProvider>();
    final selected = provider.selectedBanner;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: 'Quản Lý Banner',
        trailing: MeowCircleIconButton(
          icon: Icons.add_rounded,
          onTap: () => _openBannerDialog(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: provider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: () => provider.loadBanners(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        const MeowEditorialHero(
                          eyebrow: 'MEOW COFFEE',
                          title: 'Quản lý banner',
                          subtitle:
                              'Chọn banner để chỉnh sửa hoặc thêm hình ảnh quảng bá mới.',
                        ),
                        const SizedBox(height: 16),
                        MeowPrimaryButton(
                          label: 'Thêm banner mới',
                          icon: Icons.add_photo_alternate_outlined,
                          height: 50,
                          onPressed: () => _openBannerDialog(),
                        ),
                        const SizedBox(height: 18),
                        if (provider.banners.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text(
                                'Chưa có banner nào',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                          )
                        else
                          for (final banner in provider.banners) ...[
                            _BannerItemCard(
                              banner: banner,
                              isSelected: selected?.id == banner.id,
                              onTap: () => provider.selectBanner(banner),
                            ),
                            const SizedBox(height: 14),
                          ],
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: selected == null
                    ? const Text(
                        'Chọn banner để xem các thao tác.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Đang chọn: ${selected.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: MeowSecondaryButton(
                                  label: 'Chỉnh sửa',
                                  icon: Icons.edit_outlined,
                                  height: 44,
                                  onPressed: () =>
                                      _openBannerDialog(existing: selected),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: MeowPrimaryButton(
                                  label: 'Xóa banner',
                                  icon: Icons.delete_outline_rounded,
                                  height: 44,
                                  solidColor: AppColors.danger,
                                  onPressed: () =>
                                      _confirmDeleteBanner(selected),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerItemCard extends StatelessWidget {
  final BannerModel banner;
  final bool isSelected;
  final VoidCallback onTap;

  const _BannerItemCard({
    required this.banner,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: EdgeInsets.zero,
      borderColor: isSelected ? AppColors.brand : AppColors.border,
      borderWidth: isSelected ? 2 : 1,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 164,
            child: CachedNetworkImage(
              imageUrl: banner.bannerUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: AppColors.soft),
              errorWidget: (_, _, _) => Image.asset(
                'assets/images/banner.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    banner.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Đang chọn',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
                      ),
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

class _BannerDialog extends StatefulWidget {
  final BannerModel? existing;

  const _BannerDialog({this.existing});

  @override
  State<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<_BannerDialog> {
  late final TextEditingController _nameController;
  final ImagePicker _picker = ImagePicker();
  File? _pickedImage;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (file != null) {
        setState(() {
          _pickedImage = File(file.path);
          _errorText = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Không thể chọn ảnh: $e');
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Vui lòng nhập tên banner');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final provider = context.read<BannerProvider>();
    try {
      var url = widget.existing?.bannerUrl ?? '';
      if (_pickedImage != null) {
        url = await provider.uploadBannerImage(_pickedImage!);
      }
      if (widget.existing == null) {
        await provider.addBanner(BannerModel(name: name, bannerUrl: url));
      } else {
        await provider.updateBanner(
          widget.existing!.copyWith(name: name, bannerUrl: url),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Lỗi lưu banner: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final dialogWidth =
        (MediaQuery.of(context).size.width - 64).clamp(260.0, 350.0);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Thêm banner' : 'Chỉnh sửa banner',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              MeowFormField(
                label: 'TÊN BANNER',
                controller: _nameController,
                hintText: 'Nhập tên banner',
                readOnly: _isSaving,
              ),
              const SizedBox(height: 16),
              if (_isSaving)
                const Column(
                  children: [
                    LinearProgressIndicator(color: AppColors.brand),
                    SizedBox(height: 8),
                    Text(
                      'Đang tải lên...',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                )
              else
                MeowSecondaryButton(
                  label: _pickedImage != null ? 'Đổi ảnh khác' : 'Chọn ảnh mới',
                  icon: Icons.collections_outlined,
                  height: 46,
                  onPressed: _pickImage,
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_pickedImage != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: dialogWidth - 44,
                    height: 150,
                    child: Image.file(
                      _pickedImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.soft,
                        alignment: Alignment.center,
                        child: const Text('Không thể hiển thị ảnh đã chọn'),
                      ),
                    ),
                  ),
                ),
              ] else if (existing != null && existing.bannerUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Ảnh hiện tại:',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: dialogWidth - 44,
                    height: 150,
                    child: CachedNetworkImage(
                      imageUrl: existing.bannerUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'Lưu thay đổi',
                height: 48,
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Hủy',
                height: 44,
                onPressed: _isSaving ? null : () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
