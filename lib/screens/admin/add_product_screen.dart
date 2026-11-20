import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/env_config.dart';
import '../../services/cloudinary_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();

  File? _pickedImage;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
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
    final priceText = _priceController.text.trim();
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(priceText);

    if (name.isEmpty ||
        price == null ||
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

      final docRef = FirebaseFirestore.instance.collection('sanPham').doc();
      await docRef.set({
        'id': docRef.id,
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        'imageUrl': imageUrl,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Thêm sản phẩm mới')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ảnh sản phẩm *',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isUploading ? null : _pickImage,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _pickedImage == null && !_isUploading
                        ? colorScheme.error
                        : colorScheme.outline,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _isUploading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text('Đang tải lên...'),
                        ],
                      )
                    : _pickedImage != null
                        ? Image.file(
                            _pickedImage!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_a_photo,
                                size: 36,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 8),
                              const Text('Nhấn để chọn ảnh'),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Thông tin sản phẩm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên sản phẩm *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Giá *',
                suffixText: 'VND',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Danh mục *',
                hintText: 'Trà Hoa Quả, Trà Sữa, Sữa, Sữa Chua...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Mô tả sản phẩm *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitProduct,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isUploading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('THÊM SẢN PHẨM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
