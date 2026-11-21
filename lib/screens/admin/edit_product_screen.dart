import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/env_config.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

class EditProductScreen extends StatefulWidget {
  final String? productId;

  const EditProductScreen({
    super.key,
    required this.productId,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();

  String _currentImageUrl = '';
  File? _pickedImage;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final id = widget.productId;
    if (id == null || id.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('sanPham').doc(id).get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _nameController.text = data['name'] as String? ?? '';
        final rawPrice = data['price'];
        if (rawPrice is num) {
          _priceController.text = rawPrice == rawPrice.toInt()
              ? rawPrice.toInt().toString()
              : rawPrice.toString();
        }
        _categoryController.text = data['category'] as String? ?? 'Sữa';
        _descriptionController.text = data['description'] as String? ?? '';
        _currentImageUrl = data['imageUrl'] as String? ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải sản phẩm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    if (_isUploading) return;
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null && mounted) {
      setState(() => _pickedImage = File(file.path));
    }
  }

  Future<void> _updateProduct() async {
    final id = widget.productId;
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();

    if (id == null ||
        id.isEmpty ||
        name.isEmpty ||
        price == null ||
        category.isEmpty ||
        description.isEmpty ||
        (_pickedImage == null && _currentImageUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng điền đầy đủ thông tin bắt buộc (*)'),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      var imageUrl = _currentImageUrl;
      if (_pickedImage != null) {
        imageUrl = await CloudinaryService.instance.uploadImage(
          _pickedImage!,
          folder: EnvConfig.cloudinaryFolderProducts,
        );
      }

      await FirebaseFirestore.instance.collection('sanPham').doc(id).update({
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        'imageUrl': imageUrl,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật sản phẩm thành công!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật sản phẩm: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Chỉnh Sửa Sản Phẩm'),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ẢNH SẢN PHẨM',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MeowCard(
                      color: AppColors.soft,
                      borderRadius: 24,
                      padding: EdgeInsets.zero,
                      onTap: _isUploading ? null : _pickImage,
                      child: SizedBox(
                        height: 184,
                        width: double.infinity,
                        child: _isUploading
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: AppColors.brand,
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'Đang tải lên...',
                                    style: TextStyle(color: AppColors.brand),
                                  ),
                                ],
                              )
                            : _pickedImage != null
                                ? Image.file(
                                    _pickedImage!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                  )
                                : _currentImageUrl.isNotEmpty
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          CachedNetworkImage(
                                            imageUrl: _currentImageUrl,
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            right: 12,
                                            bottom: 12,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: const Text(
                                                'Đổi ảnh',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 36,
                                            color: AppColors.brand,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Nhấn để chọn ảnh',
                                            style: TextStyle(
                                              color: AppColors.brand,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    MeowFormField(
                      label: 'TÊN SẢN PHẨM *',
                      controller: _nameController,
                      hintText: 'Nhập tên sản phẩm',
                    ),
                    const SizedBox(height: 16),
                    MeowFormField(
                      label: 'GIÁ *',
                      controller: _priceController,
                      hintText: 'Nhập giá bán (VNĐ)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    MeowFormField(
                      label: 'DANH MỤC *',
                      controller: _categoryController,
                      hintText: 'Trà Hoa Quả, Trà Sữa, Sữa...',
                    ),
                    const SizedBox(height: 16),
                    MeowFormField(
                      label: 'MÔ TẢ SẢN PHẨM *',
                      controller: _descriptionController,
                      hintText: 'Nhập mô tả sản phẩm',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 22),
                    MeowPrimaryButton(
                      label: 'Cập nhật sản phẩm',
                      isLoading: _isUploading,
                      onPressed: _updateProduct,
                    ),
                    const SizedBox(height: 12),
                    MeowSecondaryButton(
                      label: 'Hủy',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
