import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/firestore_paths.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

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
      final doc = await FirebaseFirestore.instance
          .collection(FsCollections.users)
          .doc(uid)
          .get();

      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _user = UserModel.fromDoc(doc);
          _errorMessage = null;
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

  String _formatRole(UserRole role) => role.label;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'MC';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Thông Tin Cá Nhân'),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MeowCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 24,
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Container(
                                      width: 96,
                                      height: 96,
                                      padding: const EdgeInsets.all(3.5),
                                      decoration: const BoxDecoration(
                                        gradient: AppColors.brandGradient,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.soft,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2.5,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: (_user!.avtUrl.isNotEmpty)
                                            ? CachedNetworkImage(
                                                imageUrl: _user!.avtUrl,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, _, _) => Center(
                                                  child: Text(
                                                    _initials(_user!.name),
                                                    style: const TextStyle(
                                                      fontSize: 26,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.brand,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  _initials(_user!.name),
                                                  style: const TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.brand,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _user!.name.isNotEmpty
                                          ? _user!.name
                                          : 'Không có tên',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.inkSlate,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.soft,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _formatRole(_user!.role),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brand,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'THÔNG TIN LIÊN HỆ & TÀI KHOẢN',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.mutedLight,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    'Chi tiết',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _InfoFieldCard(
                              icon: Icons.mail_outline_rounded,
                              label: 'EMAIL',
                              value: _user!.email.isNotEmpty
                                  ? _user!.email
                                  : 'Không có email',
                            ),
                            const SizedBox(height: 12),
                            _InfoFieldCard(
                              icon: Icons.phone_outlined,
                              label: 'SỐ ĐIỆN THOẠI',
                              value: _user!.phone.isNotEmpty
                                  ? _user!.phone
                                  : 'Không có số điện thoại',
                            ),
                            const SizedBox(height: 12),
                            _InfoFieldCard(
                              icon: Icons.badge_outlined,
                              label: 'CHỨC VỤ TRONG HỆ THỐNG',
                              value: _formatRole(_user!.role),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(
                          top: BorderSide(color: AppColors.borderSubtle),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          child: MeowPrimaryButton(
                            label: 'Chỉnh sửa thông tin',
                            icon: Icons.edit_outlined,
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/editUserInfo',
                                arguments: widget.userId,
                              ).then((_) => _loadUser());
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _InfoFieldCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoFieldCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedLight,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSlate,
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
