import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa nhân viên "${user.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý nhân viên')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () async {
                await Navigator.pushNamed(context, '/add_staff');
                _loadStaffList();
              },
              child: const Text('Thêm nhân viên'),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staffList.isEmpty
              ? const Center(
                  child: Text(
                    'Chưa có nhân viên nào',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStaffList,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _staffList.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final user = _staffList[index];
                      return Card(
                        color: colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
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
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Email: ${user.email}'),
                                    Text('SĐT: ${user.soDienThoai}'),
                                    Text(
                                      'Vai trò: ${user.role}',
                                      style:
                                          TextStyle(color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _deleteStaff(user);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xóa'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
