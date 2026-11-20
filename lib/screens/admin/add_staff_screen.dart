import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/env_config.dart';
import '../../models/user_model.dart';

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController(text: 'Nhân Viên');
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
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
    final role = _roleController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || role.isEmpty || phone.isEmpty || email.isEmpty) {
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
        avtUrl: '',
        email: email,
        name: name,
        role: role,
        soDienThoai: phone,
      );

      await FirebaseFirestore.instance
          .collection('uSer')
          .doc(uid)
          .set(user.toMap());

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
              'Thêm nhân viên thành công! Mật khẩu đã gửi đến email $email',
            ),
          ),
        );
        Navigator.pop(context);
      } catch (emailErr) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Thêm nhân viên thành công nhưng gửi email thất bại: $emailErr';
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
      appBar: AppBar(title: const Text('Thêm nhân viên mới')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên nhân viên',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(
                labelText: 'Chức vụ',
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
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Thêm nhân viên'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
