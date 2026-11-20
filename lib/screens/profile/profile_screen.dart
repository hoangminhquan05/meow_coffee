import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/bottom_nav_bar.dart';

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
    final uid = _userId;
    if (uid == null) {
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
        final data = doc.data()!;
        setState(() {
          _role = data['role'] as String?;
          _avtUrl = data['avtUrl'] as String?;
          _name = data['name'] as String?;
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

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Chắc chắn',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _userId;

    final menuItems = <_ProfileMenuItem>[
      _ProfileMenuItem(
        title: 'Thông tin tài khoản',
        icon: Icons.person,
        onTap: () {
          if (uid != null) {
            Navigator.pushNamed(context, '/thongtincanhan', arguments: uid)
                .then((_) => _loadUserProfile());
          }
        },
      ),
      _ProfileMenuItem(
        title: 'Đổi mật khẩu',
        icon: Icons.password,
        onTap: () => Navigator.pushNamed(context, '/change_password'),
      ),
      if (_role == 'ADMIN') ...[
        _ProfileMenuItem(
          title: 'Quản lý sản phẩm',
          icon: Icons.production_quantity_limits,
          onTap: () => Navigator.pushNamed(context, '/adminproduct'),
        ),
        _ProfileMenuItem(
          title: 'Quản lý nhân viên',
          icon: Icons.people,
          onTap: () => Navigator.pushNamed(context, '/staff_management'),
        ),
        _ProfileMenuItem(
          title: 'Quản lý banner',
          icon: Icons.collections,
          onTap: () => Navigator.pushNamed(context, '/bannerManagement'),
        ),
      ],
      _ProfileMenuItem(
        title: 'Thống kê doanh thu',
        icon: Icons.stacked_bar_chart,
        onTap: () => Navigator.pushNamed(context, '/statistics'),
      ),
      _ProfileMenuItem(
        title: 'Quản lý bàn',
        icon: Icons.table_bar,
        onTap: () => Navigator.pushNamed(context, '/table_management'),
      ),
      _ProfileMenuItem(
        title: 'Đăng Xuất',
        icon: Icons.exit_to_app,
        onTap: _confirmLogout,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (uid != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'User ID: $uid',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                ClipOval(
                  child: Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey.shade300,
                    child: (_avtUrl != null && _avtUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: _avtUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const Center(
                              child: CircularProgressIndicator(),
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
                const SizedBox(height: 16),
                Text(
                  (_name != null && _name!.trim().isNotEmpty)
                      ? _name!.trim()
                      : (FirebaseAuth.instance.currentUser?.displayName
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? FirebaseAuth.instance.currentUser!.displayName!
                          : (_isLoading ? '' : 'Người dùng')),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.coffeeBrown,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoading
                      ? 'Đang tải dữ liệu...'
                      : (_errorMessage ?? _role ?? 'Nhân viên'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _role == 'ADMIN' ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
                ...menuItems.map(
                  (item) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black87, width: 1),
                    ),
                    child: ListTile(
                      onTap: item.onTap,
                      leading: Icon(item.icon, color: AppColors.coffeeBrown),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4E342E),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.coffeeBrown,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}
