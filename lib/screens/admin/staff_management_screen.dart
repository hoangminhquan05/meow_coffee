import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
          .collection('uSer')
          .where('role', isEqualTo: 'Nhân Viên')
          .get();
      if (!mounted) return;
      setState(() {
        _staffList = snapshot.docs
            .map((doc) => UserModel.fromMap(doc.data(), docId: doc.id))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('StaffManagementScreen._loadStaffList error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteStaff(UserModel user) async {
    final confirmed = await showMeowConfirmDialog(
      context,
      title: 'Xóa nhân viên',
      message:
          'Bạn có chắc chắn muốn xóa nhân viên “${user.name}” khỏi hệ thống?',
      confirmLabel: 'Xóa nhân viên',
      cancelLabel: 'Hủy',
      isDanger: true,
    );

    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance
          .collection('uSer')
          .doc(user.uid)
          .delete();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == user.uid) {
        await currentUser.delete();
      }

      if (!mounted) return;
      setState(() {
        _staffList.removeWhere((item) => item.uid == user.uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa nhân viên ${user.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa nhân viên: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Quản Lý Nhân Viên'),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _loadStaffList,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  const MeowEditorialHero(
                    eyebrow: 'MEOW COFFEE',
                    title: 'Đội ngũ Meow Coffee',
                    subtitle: 'Thông tin nhân viên và vai trò trong cửa hàng.',
                  ),
                  const SizedBox(height: 16),
                  MeowPrimaryButton(
                    label: 'Thêm nhân viên',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/add_staff');
                      _loadStaffList();
                    },
                  ),
                  const SizedBox(height: 18),
                  if (_staffList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'Chưa có nhân viên nào',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    )
                  else
                    for (final user in _staffList) ...[
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
                                    '${user.soDienThoai} • ${user.role}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    onTap: () => _deleteStaff(user),
                                    child: const Text(
                                      'Xóa nhân viên',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.danger,
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
            ),
    );
  }
}
