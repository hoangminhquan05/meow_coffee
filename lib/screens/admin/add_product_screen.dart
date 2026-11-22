import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/env_config.dart';
import '../../core/firestore_paths.dart';
import '../../models/product.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';
import '../../widgets/price_inputs.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameController = TextEditingController();
  final _price = PriceFormController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();

  File? _pickedImage;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _price.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isUploading) return;
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null && mounted) {
      setState(() => _pickedImage = File(file.path));
    }
  }

  Future<void> _submitProduct() async {
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();
    final prices = _price.build();

    if (name.isEmpty ||
        prices == null ||
        category.isEmpty ||
        description.isEmpty ||
        _pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng điền đầy đủ thông tin bắt buộc (*)'),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final imageUrl = await CloudinaryService.instance.uploadImage(
        _pickedImage!,
        folder: EnvConfig.cloudinaryFolderProducts,
      );

      await FirebaseFirestore.instance.collection(FsCollections.products).add({
        ...Product(
          name: name,
          category: category,
          description: description,
          imageUrl: imageUrl,
          prices: prices,
        ).toMap(),
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thêm sản phẩm thành công!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi thêm sản phẩm: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Thêm Sản Phẩm'),
      body: SafeArea(
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
                            CircularProgressIndicator(color: AppColors.brand),
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
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 36,
                                  color: AppColors.brand,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Chọn ảnh sản phẩm',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brand,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Nhấn để chọn ảnh từ thư viện',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
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
              PriceInputs(controller: _price),
              const SizedBox(height: 16),
              MeowFormField(
                label: 'DANH MỤC *',
                controller: _categoryController,
                hintText: 'Cà phê, Trà, Bánh...',
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
                label: 'Thêm sản phẩm',
                isLoading: _isUploading,
                onPressed: _submitProduct,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
