import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/env_config.dart';
import '../../theme/app_theme.dart';

enum _ChangePasswordStep { email, otp, password }

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with SingleTickerProviderStateMixin {
  static const Color _darkBrown = Color(0xFF4E342E);
  static const Color _borderBrown = Color(0xFFBCAAA4);

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final AnimationController _rotationController;

  _ChangePasswordStep _step = _ChangePasswordStep.email;
  String _generatedOtp = '';
  bool _isLoading = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  static final _emailRegex = RegExp(r'^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$');

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _generateOtp() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (email.isEmpty) {
      _showMessage('Vui lòng nhập email');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _showMessage('Định dạng email không hợp lệ');
      return;
    }
    if (email != currentUser?.email) {
      _showMessage('Email không khớp với tài khoản đã đăng ký');
      return;
    }

    setState(() => _isLoading = true);
    _generatedOtp = _generateOtp();

    try {
      final emailJsServiceId = EnvConfig.emailJsServiceId;
      final emailJsTemplateId = EnvConfig.emailJsOtpTemplateId;
      final emailJsPublicKey = EnvConfig.emailJsPublicKey;
      final emailJsPrivateKey = EnvConfig.emailJsPrivateKey;

      if (emailJsServiceId.isEmpty ||
          emailJsTemplateId.isEmpty ||
          emailJsPublicKey.isEmpty) {
        _showMessage('Chưa cấu hình EmailJS trong file .env');
        return;
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
            'to_email': email,
            'name': email,
            'otp': _generatedOtp,
          },
        }),
      );

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showMessage('Mã OTP đã được gửi đến email của bạn');
        setState(() => _step = _ChangePasswordStep.otp);
      } else {
        _showMessage(
          'Gửi OTP thất bại (mã ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      _showMessage('Lỗi kết nối: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _verifyOtp() {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      _showMessage('Vui lòng nhập mã OTP');
      return;
    }
    if (otp != _generatedOtp) {
      _showMessage('Mã OTP không chính xác, vui lòng kiểm tra lại');
      return;
    }
    setState(() => _step = _ChangePasswordStep.password);
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword != confirmPassword) {
      _showMessage('Mật khẩu mới không khớp');
      return;
    }
    if (newPassword.length < 6) {
      _showMessage('Mật khẩu phải có ít nhất 6 ký tự');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final email = currentUser?.email;
    if (currentUser == null || email == null) {
      _showMessage('Phiên đăng nhập không hợp lệ');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await currentUser.reauthenticateWithCredential(credential);
      await currentUser.updatePassword(newPassword);

      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      await _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showMessage('Mật khẩu hiện tại không đúng');
      } else {
        _showMessage('Đổi mật khẩu thất bại: ${e.message ?? e.code}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Thành công!',
          style: TextStyle(fontWeight: FontWeight.bold, color: _darkBrown),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mật khẩu đã được thay đổi thành công!'),
            const SizedBox(height: 16),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF8BC34A).withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8BC34A), width: 2),
              ),
              alignment: Alignment.center,
              child: const Text(
                '✓',
                style: TextStyle(
                  fontSize: 40,
                  color: Color(0xFF8BC34A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coffeeBrown,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('OK', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _brownFieldDecoration({
    String? label,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderBrown),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.coffeeBrown, width: 2),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: RotationTransition(
              turns: _rotationController,
              child: _DecorativeCircle(size: 120, emoji: '☕', fontSize: 40),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: RotationTransition(
              turns: _rotationController,
              child: _DecorativeCircle(size: 100, emoji: '🔒', fontSize: 30),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: const Text(
                    'Đổi Mật Khẩu',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: _darkBrown,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.coffeeBrown),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.coffeeBrown.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  AppColors.coffeeBrown.withValues(alpha: 0.2),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🔑', style: TextStyle(fontSize: 40)),
                        ),
                        const SizedBox(height: 16),
                        if (_step == _ChangePasswordStep.email)
                          _buildEmailStep()
                        else if (_step == _ChangePasswordStep.otp)
                          _buildOtpStep()
                        else
                          _buildPasswordStep(),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            5,
                            (_) => Text(
                              '•',
                              style: TextStyle(
                                fontSize: 20,
                                color: AppColors.coffeeBrown
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      children: [
        const Text(
          'Xác thực Email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _darkBrown,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vui lòng nhập email đã đăng ký tài khoản',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.coffeeBrown.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _brownFieldDecoration(label: 'Email'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coffeeBrown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const Text(
                    'Gửi OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      children: [
        const Text(
          'Xác thực OTP',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _darkBrown,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vui lòng nhập mã OTP đã gửi đến email của bạn',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.coffeeBrown.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          decoration: _brownFieldDecoration(label: 'Mã OTP'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coffeeBrown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Xác nhận OTP',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            _otpController.clear();
            setState(() => _step = _ChangePasswordStep.email);
          },
          child: const Text('Quay lại nhập email'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Text(
            'Đổi Mật Khẩu',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _darkBrown,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Vui lòng nhập mật khẩu mới',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.coffeeBrown.withValues(alpha: 0.8),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _currentPasswordController,
          obscureText: !_showCurrentPassword,
          decoration: _brownFieldDecoration(
            label: 'Mật khẩu hiện tại',
            suffixIcon: IconButton(
              icon: Icon(
                _showCurrentPassword ? Icons.visibility : Icons.visibility_off,
                color: AppColors.coffeeBrown.withValues(alpha: 0.6),
              ),
              onPressed: () => setState(
                () => _showCurrentPassword = !_showCurrentPassword,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newPasswordController,
          obscureText: !_showNewPassword,
          decoration: _brownFieldDecoration(
            label: 'Mật khẩu mới',
            suffixIcon: IconButton(
              icon: Icon(
                _showNewPassword ? Icons.visibility : Icons.visibility_off,
                color: AppColors.coffeeBrown.withValues(alpha: 0.6),
              ),
              onPressed: () =>
                  setState(() => _showNewPassword = !_showNewPassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          obscureText: !_showConfirmPassword,
          decoration: _brownFieldDecoration(
            label: 'Nhập lại mật khẩu mới',
            suffixIcon: IconButton(
              icon: Icon(
                _showConfirmPassword ? Icons.visibility : Icons.visibility_off,
                color: AppColors.coffeeBrown.withValues(alpha: 0.6),
              ),
              onPressed: () => setState(
                () => _showConfirmPassword = !_showConfirmPassword,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coffeeBrown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const Text(
                    'Đổi Mật Khẩu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final String emoji;
  final double fontSize;

  const _DecorativeCircle({
    required this.size,
    required this.emoji,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.coffeeBrown.withValues(alpha: 0.05),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.coffeeBrown.withValues(alpha: 0.1),
        ),
      ),
      alignment: Alignment.center,
      child: Opacity(
        opacity: 0.25,
        child: Text(emoji, style: TextStyle(fontSize: fontSize)),
      ),
    );
  }
}
