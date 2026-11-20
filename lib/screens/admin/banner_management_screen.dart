import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/banner_model.dart';
import '../../providers/banner_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BannerProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final selected = provider.selectedBanner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Banner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Thêm banner',
            onPressed: () => _openBannerDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.banners.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có banner nào',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: provider.banners.length,
                        itemBuilder: (context, index) {
                          final banner = provider.banners[index];
                          final isSelected = selected?.id == banner.id;

                          return Card(
                            margin: const EdgeInsets.all(8),
                            elevation: isSelected ? 8 : 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => provider.selectBanner(banner),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: CachedNetworkImage(
                                      imageUrl: banner.bannerUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => Container(
                                        color: Colors.grey.shade200,
                                      ),
                                      errorWidget: (_, _, _) => Image.asset(
                                        'assets/images/banner.jpg',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      banner.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (selected != null)
            SafeArea(
              top: false,
              child: Card(
                margin: const EdgeInsets.all(12),
                elevation: 6,
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🎯 Đang chọn: ${selected.name}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _openBannerDialog(existing: selected),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.edit),
                              label: const Text('Chỉnh sửa'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => provider.deleteBanner(selected.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.delete),
                              label: const Text('Xóa'),
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
    final dialogWidth = (MediaQuery.of(context).size.width - 80).clamp(240.0, 340.0);

    return AlertDialog(
      title: Text(existing == null ? 'Thêm Banner' : 'Chỉnh sửa Banner'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Tên banner',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_isSaving)
                const Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Đang tải lên...'),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.collections),
                  label: Text(
                    _pickedImage != null ? 'Đổi ảnh khác' : 'Chọn ảnh mới',
                  ),
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_pickedImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: dialogWidth,
                    height: 160,
                    child: Image.file(
                      _pickedImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Text('Không thể hiển thị ảnh đã chọn'),
                      ),
                    ),
                  ),
                )
              else if (existing != null && existing.bannerUrl.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ảnh hiện tại:'),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: dialogWidth,
                        height: 160,
                        child: CachedNetworkImage(
                          imageUrl: existing.bannerUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('Lưu thay đổi'),
        ),
      ],
    );
  }
}
