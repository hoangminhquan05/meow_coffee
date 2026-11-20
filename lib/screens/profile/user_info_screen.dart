import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

class UserInfoScreen extends StatefulWidget {
  final String? userId;

  const UserInfoScreen({
    super.key,
    required this.userId,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  UserModel? _user;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = widget.userId;
    if (uid == null || uid.isEmpty) {
      setState(() {
        _errorMessage = 'Không có ID người dùng';
        _isLoading = false;
      });
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('uSer').doc(uid).get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        setState(() {
          _user = UserModel.fromMap(doc.data()!, docId: doc.id);
          _isLoading = false;
        });
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

  String _formatRole(String role) {
    switch (role) {
      case 'Nhân Viên':
        return 'Nhân viên';
      case 'ADMIN':
        return 'Quản lý';
      default:
        return role.isNotEmpty ? role : 'Không xác định';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Thông Tin Cá Nhân',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.deepPurple,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      ClipOval(
                        child: Container(
                          width: 120,
                          height: 120,
                          color: Colors.grey.shade300,
                          child: (_user!.avtUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: _user!.avtUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => Image.asset(
                                    'assets/images/coffee_login.png',
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/coffee_login.png',
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _user!.name.isNotEmpty ? _user!.name : 'Không có tên',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        title: 'Email',
                        value: _user!.email.isNotEmpty
                            ? _user!.email
                            : 'Không có email',
                      ),
                      const SizedBox(height: 8),
                      _InfoCard(
                        title: 'Số điện thoại',
                        value: _user!.soDienThoai.isNotEmpty
                            ? _user!.soDienThoai
                            : 'Không có số điện thoại',
                      ),
                      const SizedBox(height: 8),
                      _InfoCard(
                        title: 'Chức vụ',
                        value: _formatRole(_user!.role),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/editUserInfo',
                              arguments: widget.userId,
                            ).then((_) => _loadUser());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Chỉnh sửa thông tin',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;

  const _InfoCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        color: const Color(0xFFF5F5F5),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
