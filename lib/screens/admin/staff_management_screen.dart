import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/firestore_paths.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<UserModel> _staffList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaffList();
  }

  Future<void> _loadStaffList() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FsCollections.users)
          .where(
            'role',
            whereIn: [UserRole.staff.value, UserRole.shipper.value],
          )
          .get();
      if (!mounted) return;
      setState(() {
        _staffList = snapshot.docs.map(UserModel.fromDoc).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('StaffManagementScreen._loadStaffList error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Khóa / mở khóa tài khoản thay vì xóa, để lịch sử đơn vẫn nguyên vẹn.
  /// Nhân viên bị khóa đang đăng nhập sẽ bị đăng xuất ngay (Q14).
  Future<void> _toggleLock(UserModel user) async {
    final lock = user.isActive;
    final confirmed = await showMeowConfirmDialog(
      context,
      title: lock ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
      message: lock
          ? 'Khóa “${user.name}”? Người này sẽ bị đăng xuất và không đăng nhập được nữa. Lịch sử đơn vẫn giữ nguyên.'
          : 'Mở khóa cho “${user.name}” đăng nhập lại?',
      confirmLabel: lock ? 'Khóa' : 'Mở khóa',
      cancelLabel: 'Hủy',
      isDanger: lock,
      icon: lock ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
    );
    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance
          .collection(FsCollections.users)
          .doc(user.uid)
          .update({'is_active': !lock});
      if (!mounted) return;
      setState(() {
        final i = _staffList.indexWhere((u) => u.uid == user.uid);
        if (i >= 0) _staffList[i] = user.copyWith(isActive: !lock);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lock
                ? 'Đã khóa tài khoản ${user.name}'
                : 'Đã mở khóa tài khoản ${user.name}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi cập nhật tài khoản: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: const MeowHeader(title: 'Quản Lý Nhân Viên'),
        body: Column(
          children: [
            const TabBar(
              labelColor: AppColors.brand,
              indicatorColor: AppColors.brand,
              unselectedLabelColor: AppColors.muted,
              tabs: [
                Tab(text: 'Nhân viên'),
                Tab(text: 'Shipper'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.brand),
                    )
                  : TabBarView(
                      children: [
                        _buildList(UserRole.staff),
                        _buildList(UserRole.shipper),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(UserRole role) {
    final users = _staffList.where((u) => u.role == role).toList();
    final isShipper = role == UserRole.shipper;
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadStaffList,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          MeowPrimaryButton(
            label: isShipper ? 'Thêm shipper' : 'Thêm nhân viên',
            icon: isShipper
                ? Icons.delivery_dining_rounded
                : Icons.person_add_alt_1_rounded,
            onPressed: () async {
              await Navigator.pushNamed(context, '/add_staff', arguments: role);
              _loadStaffList();
            },
          ),
          const SizedBox(height: 18),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  isShipper ? 'Chưa có shipper nào' : 'Chưa có nhân viên nào',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            for (final user in users) ...[
              MeowCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: user.avtUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: user.avtUrl,
                                fit: BoxFit.cover,
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${user.phone} • ${user.role.label}'
                            '${user.isActive ? '' : ' • ĐÃ KHÓA'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: user.isActive
                                  ? AppColors.muted
                                  : AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => _toggleLock(user),
                            child: Text(
                              user.isActive
                                  ? 'Khóa tài khoản'
                                  : 'Mở khóa tài khoản',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: user.isActive
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
