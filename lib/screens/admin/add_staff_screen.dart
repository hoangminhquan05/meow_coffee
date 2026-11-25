import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/env_config.dart';
import '../../core/enums.dart';
import '../../core/firestore_paths.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

/// Admin tạo tài khoản nhân viên hoặc shipper (O18), gửi mật khẩu tạm qua email.
class AddStaffScreen extends StatefulWidget {
  /// Vai trò chọn sẵn (mở từ tab Shipper thì là shipper).
  final UserRole initialRole;

  const AddStaffScreen({super.key, this.initialRole = UserRole.staff});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  late UserRole _role = widget.initialRole;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _sendWelcomeEmail({
    required String staffEmail,
    required String staffName,
    required String tempPassword,
  }) async {
    final emailJsServiceId = EnvConfig.emailJsServiceId;
    final emailJsTemplateId = EnvConfig.emailJsWelcomeTemplateId;
    final emailJsPublicKey = EnvConfig.emailJsPublicKey;
    final emailJsPrivateKey = EnvConfig.emailJsPrivateKey;

    if (emailJsServiceId.isEmpty ||
        emailJsTemplateId.isEmpty ||
        emailJsPublicKey.isEmpty) {
      throw StateError('Chưa cấu hình EmailJS trong file .env');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Origin': EnvConfig.emailJsOrigin,
      if (emailJsPrivateKey.isNotEmpty)
        'Authorization': 'Bearer $emailJsPrivateKey',
    };

    final response = await http.post(
      Uri.parse(EnvConfig.emailJsApiUrl),
      headers: headers,
      body: jsonEncode({
        'service_id': emailJsServiceId,
        'template_id': emailJsTemplateId,
        'user_id': emailJsPublicKey,
        'template_params': {
          'to_email': staffEmail,
          'name': staffName,
          'password': tempPassword,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mã lỗi: ${response.statusCode}. ${response.body}');
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng điền đầy đủ thông tin');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final tempPassword = _generateRandomPassword();
    FirebaseApp? secondaryApp;
    try {
      final secondaryAppName =
          'StaffCreate_${DateTime.now().millisecondsSinceEpoch}';
      secondaryApp = await Firebase.initializeApp(
        name: secondaryAppName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );
      final uid = credential.user?.uid ?? '';
      await credential.user?.updateDisplayName(name);
      await secondaryAuth.signOut();

      final user = UserModel(
        uid: uid,
        email: email,
        name: name,
        role: _role,
        phone: phone,
      );

      await FirebaseFirestore.instance
          .collection(FsCollections.users)
          .doc(uid)
          .set({...user.toMap(), 'created_at': FieldValue.serverTimestamp()});

      try {
        await _sendWelcomeEmail(
          staffEmail: email,
          staffName: name,
          tempPassword: tempPassword,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã thêm ${_role.label.toLowerCase()} $name! Mật khẩu đã gửi đến email $email',
            ),
          ),
        );
        Navigator.pop(context);
      } catch (emailErr) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Đã tạo tài khoản nhưng gửi email thất bại: $emailErr';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message ?? 'Lỗi khi tạo tài khoản');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Lỗi: $e');
    } finally {
      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: _role == UserRole.shipper ? 'Thêm Shipper' : 'Thêm Nhân Viên',
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MeowEditorialHero(
                eyebrow: 'MEOW COFFEE',
                title: 'Thêm tài khoản mới',
                subtitle: 'Tạo tài khoản nhân viên bán hàng hoặc shipper và gửi mật khẩu tạm qua email.',
              ),
              const SizedBox(height: 20),
              const Text(
                'VAI TRÒ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<UserRole>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: UserRole.staff,
                    icon: Icon(Icons.storefront_outlined),
                    label: Text('Nhân viên'),
                  ),
                  ButtonSegment(
                    value: UserRole.shipper,
                    icon: Icon(Icons.delivery_dining_outlined),
                    label: Text('Shipper'),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (v) => setState(() => _role = v.first),
              ),
              const SizedBox(height: 16),
              MeowFormField(
                label: 'HỌ VÀ TÊN',
                controller: _nameController,
                hintText: 'Nhập họ và tên',
              ),
              const SizedBox(height: 16),
              MeowFormField(
                label: 'SỐ ĐIỆN THOẠI',
                controller: _phoneController,
                hintText: 'Nhập số điện thoại',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              MeowFormField(
                label: 'EMAIL',
                controller: _emailController,
                hintText: 'Nhập email đăng nhập',
                keyboardType: TextInputType.emailAddress,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              MeowPrimaryButton(
                label: _role == UserRole.shipper
                    ? 'Thêm shipper'
                    : 'Thêm nhân viên',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
