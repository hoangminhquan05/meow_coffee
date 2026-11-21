import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/env_config.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

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
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Chỉnh Sửa Thông Tin'),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 160,
                          child: MeowSecondaryButton(
                            label: 'Thử lại',
                            onPressed: _loadUserData,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const MeowEditorialHero(
                        eyebrow: 'MEOW COFFEE',
                        title: 'Thông tin của bạn',
                        subtitle: 'Cập nhật tên và số điện thoại liên hệ.',
                      ),
                      const SizedBox(height: 18),
                      MeowCard(
                        padding: const EdgeInsets.all(16),
                        onTap: _pickImage,
                        child: Row(
                          children: [
                            ClipOval(
                              child: SizedBox(
                                width: 54,
                                height: 54,
                                child: _buildAvatar(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ảnh đại diện',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Thay đổi ảnh',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.photo_camera_outlined,
                              color: AppColors.brand,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      MeowFormField(
                        label: 'TÊN',
                        controller: _nameController,
                        hintText: 'Nhập họ và tên',
                      ),
                      const SizedBox(height: 18),
                      MeowFormField(
                        label: 'SỐ ĐIỆN THOẠI',
                        controller: _phoneController,
                        hintText: 'Nhập số điện thoại',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 22),
                      MeowPrimaryButton(
                        label: 'Lưu thay đổi',
                        isLoading: _isSaving,
                        onPressed: _saveChanges,
                      ),
                      const SizedBox(height: 12),
                      MeowSecondaryButton(
                        label: 'Hủy thay đổi',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
    );
  }
}
