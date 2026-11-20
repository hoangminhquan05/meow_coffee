import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/env_config.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';

class EditUserInfoScreen extends StatefulWidget {
  final String? userId;

  const EditUserInfoScreen({
    super.key,
    required this.userId,
  });

  @override
  State<EditUserInfoScreen> createState() => _EditUserInfoScreenState();
}

class _EditUserInfoScreenState extends State<EditUserInfoScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _picker = ImagePicker();

  String _avtUrl = '';
  File? _pickedImage;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = widget.userId;
    if (uid == null || uid.isEmpty) {
      setState(() {
        _errorMessage = 'Không có ID người dùng';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc =
          await FirebaseFirestore.instance.collection('uSer').doc(uid).get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _phoneController.text = data['soDienThoai'] as String? ?? '';
        _avtUrl = data['avtUrl'] as String? ?? '';
        setState(() => _isLoading = false);
      } else {
        setState(() {
          _errorMessage = 'Không tìm thấy thông tin người dùng';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khi tải dữ liệu: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null && mounted) {
      setState(() => _pickedImage = File(file.path));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ảnh đã được chọn')),
      );
    }
  }

  Future<void> _saveChanges() async {
    final uid = widget.userId;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đầy đủ thông tin')),
      );
      return;
    }
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có ID người dùng')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      var updatedAvtUrl = _avtUrl;
      if (_pickedImage != null) {
        if (_avtUrl.isNotEmpty) {
          await CloudinaryService.instance.deleteImageByUrl(_avtUrl);
        }
        updatedAvtUrl = await CloudinaryService.instance.uploadImage(
          _pickedImage!,
          folder: EnvConfig.cloudinaryFolderAvatars,
          publicId: 'user_$uid',
        );
      }

      await FirebaseFirestore.instance.collection('uSer').doc(uid).update({
        'name': name,
        'soDienThoai': phone,
        'avtUrl': updatedAvtUrl,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật thành công')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildAvatar() {
    if (_pickedImage != null) {
      return Image.file(_pickedImage!, fit: BoxFit.cover);
    }
    if (_avtUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _avtUrl,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) =>
            Image.asset('assets/images/user_df.jpg', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/user_df.jpg', fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chỉnh Sửa Thông Tin',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.deepPurple,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(
                          children: [
                            ClipOval(
                              child: Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey.shade300,
                                child: _buildAvatar(),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _pickImage,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0x80000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_enhance,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Tên',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Lưu Thay Đổi',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
