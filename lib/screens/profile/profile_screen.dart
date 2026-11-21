import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/meow_ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _role;
  String? _avtUrl;
  String? _name;
  bool _isLoading = true;
  String? _errorMessage;

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;
    if (uid == null) {
      setState(() {
        _errorMessage = 'Không có ID người dùng';
        _isLoading = false;
      });
      return;
    }

    try {
      final usersCol = FirebaseFirestore.instance.collection('uSer');
      Map<String, dynamic>? data;

      final doc = await usersCol.doc(uid).get();
      if (doc.exists && doc.data() != null) {
        data = doc.data();
      } else {
        final byUid =
            await usersCol.where('uid', isEqualTo: uid).limit(1).get();
        if (byUid.docs.isNotEmpty) {
          data = byUid.docs.first.data();
        } else if (currentUser?.email != null &&
            currentUser!.email!.isNotEmpty) {
          final byEmail = await usersCol
              .where('email', isEqualTo: currentUser.email)
              .limit(1)
              .get();
          if (byEmail.docs.isNotEmpty) {
            data = byEmail.docs.first.data();
          }
        }
      }

      if (!mounted) return;
      if (data != null) {
        setState(() {
          _role = data!['role'] as String?;
          _avtUrl = data['avtUrl'] as String?;
          _name = data['name'] as String?;
          _errorMessage = null;
          _isLoading = false;
        });
      } else {
        setState(() {
          _role = 'Nhân viên';
          _errorMessage = null;
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

  Future<void> _confirmLogout() async {
    final confirmed = await showMeowConfirmDialog(
      context,
      title: 'Xác nhận đăng xuất',
      message: 'Bạn có chắc chắn muốn đăng xuất khỏi Meow Coffee?',
      confirmLabel: 'Đăng xuất',
      cancelLabel: 'Hủy',
      isDanger: true,
      icon: Icons.logout_rounded,
    );

    if (confirmed) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _userId;
    final displayName = (_name != null && _name!.trim().isNotEmpty)
        ? _name!.trim()
        : (FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ==
                true
            ? FirebaseAuth.instance.currentUser!.displayName!
            : (_isLoading ? 'Đang tải...' : 'Người dùng'));

    final isAdmin = _role == 'ADMIN';

    final menuItems = <_ProfileMenuItem>[
      _ProfileMenuItem(
        title: 'Thông tin tài khoản',
        subtitle: 'Xem và sửa thông tin cá nhân',
        icon: Icons.person_outline_rounded,
        onTap: () {
          if (uid != null) {
            Navigator.pushNamed(context, '/thongtincanhan', arguments: uid)
                .then((_) => _loadUserProfile());
          }
        },
      ),
      _ProfileMenuItem(
        title: 'Đổi mật khẩu',
        subtitle: 'Cập nhật bảo mật tài khoản',
        icon: Icons.lock_outline_rounded,
        onTap: () => Navigator.pushNamed(context, '/change_password'),
      ),
      if (isAdmin) ...[
        _ProfileMenuItem(
          title: 'Quản lý sản phẩm',
          subtitle: 'Thực đơn, công thức, giá niêm yết',
          icon: Icons.local_cafe_outlined,
          isAdminOnly: true,
          onTap: () => Navigator.pushNamed(context, '/adminproduct'),
        ),
        _ProfileMenuItem(
          title: 'Quản lý nhân viên',
          subtitle: 'Danh sách nhân sự, tài khoản',
          icon: Icons.people_outline_rounded,
          isAdminOnly: true,
          onTap: () => Navigator.pushNamed(context, '/staff_management'),
        ),
        _ProfileMenuItem(
          title: 'Quản lý banner',
          subtitle: 'Hình ảnh quảng bá trang chủ',
          icon: Icons.collections_outlined,
          isAdminOnly: true,
          onTap: () => Navigator.pushNamed(context, '/bannerManagement'),
        ),
      ],
      _ProfileMenuItem(
        title: 'Thống kê doanh thu',
        subtitle: 'Báo cáo doanh thu & lịch sử đơn hàng',
        icon: Icons.bar_chart_rounded,
        hasLiveDot: true,
        onTap: () => Navigator.pushNamed(context, '/statistics'),
      ),
      _ProfileMenuItem(
        title: 'Quản lý bàn',
        subtitle: 'Sơ đồ bàn và trạng thái phục vụ',
        icon: Icons.table_bar_outlined,
        onTap: () => Navigator.pushNamed(context, '/table_management'),
      ),
      _ProfileMenuItem(
        title: 'Đăng Xuất',
        subtitle: 'Thoát tài khoản khỏi thiết bị',
        icon: Icons.logout_rounded,
        isDanger: true,
        onTap: _confirmLogout,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: _loadUserProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileHeroCard(
                  avtUrl: _avtUrl,
                  displayName: displayName,
                  roleText: _isLoading
                      ? 'Đang tải...'
                      : (_errorMessage ?? _role ?? 'Nhân viên'),
                  isAdmin: isAdmin,
                  onEditAvatar: () {
                    if (uid != null) {
                      Navigator.pushNamed(
                        context,
                        '/thongtincanhan',
                        arguments: uid,
                      ).then((_) => _loadUserProfile());
                    }
                  },
                ),
                const SizedBox(height: 22),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'CHỨC NĂNG HỆ THỐNG',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in menuItems) ...[
                  _ProfileMenuTile(item: item),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  final String? avtUrl;
  final String displayName;
  final String roleText;
  final bool isAdmin;
  final VoidCallback onEditAvatar;

  const _ProfileHeroCard({
    required this.avtUrl,
    required this.displayName,
    required this.roleText,
    required this.isAdmin,
    required this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -36,
            top: -36,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -28,
            bottom: -28,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              children: [
                GestureDetector(
                  onTap: onEditAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: (avtUrl != null && avtUrl!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: avtUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(
                                    color: AppColors.soft,
                                    alignment: Alignment.center,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                  errorWidget: (_, _, _) => Image.asset(
                                    'assets/images/user_df.jpg',
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/user_df.jpg',
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Meow Coffee',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEEE6FF),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isAdmin
                          ? const Color(0xFFFECDD3)
                          : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isAdmin ? AppColors.danger : AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        roleText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isAdmin ? AppColors.danger : AppColors.success,
                        ),
                      ),
                    ],
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

class _ProfileMenuTile extends StatelessWidget {
  final _ProfileMenuItem item;

  const _ProfileMenuTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: item.onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.isDanger ? AppColors.dangerSoft : AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              size: 20,
              color: item.isDanger ? AppColors.danger : AppColors.brand,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: item.isDanger
                              ? AppColors.danger
                              : AppColors.inkSlate,
                        ),
                      ),
                    ),
                    if (item.isAdminOnly) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.soft,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: item.isDanger
                        ? const Color(0xFFFB7185)
                        : AppColors.mutedLight,
                  ),
                ),
              ],
            ),
          ),
          if (item.hasLiveDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: item.isDanger ? AppColors.danger : AppColors.mutedLight,
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isAdminOnly;
  final bool isDanger;
  final bool hasLiveDot;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isAdminOnly = false,
    this.isDanger = false,
    this.hasLiveDot = false,
    required this.onTap,
  });
}
