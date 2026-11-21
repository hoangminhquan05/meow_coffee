import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/env_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

enum _ChangePasswordStep { email, otp, password }

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ChangePasswordStep _step = _ChangePasswordStep.email;
  String _generatedOtp = '';
  bool _isLoading = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  static final _emailRegex = RegExp(r'^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$');

  @override
  void dispose() {
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
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Đổi mật khẩu thành công',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Mật khẩu của bạn đã được cập nhật.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'Về trang chủ',
                height: 48,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  int get _stepIndex => switch (_step) {
        _ChangePasswordStep.email => 1,
        _ChangePasswordStep.otp => 2,
        _ChangePasswordStep.password => 3,
      };

  String get _headerTitle => switch (_step) {
        _ChangePasswordStep.email => 'Xác Thực Email',
        _ChangePasswordStep.otp => 'Xác Thực OTP',
        _ChangePasswordStep.password => 'Đổi Mật Khẩu',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(title: _headerTitle),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VerificationProgressBar(currentStep: _stepIndex),
              const SizedBox(height: 18),
              if (_step == _ChangePasswordStep.email)
                _buildEmailStep()
              else if (_step == _ChangePasswordStep.otp)
                _buildOtpStep()
              else
                _buildPasswordStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MeowEditorialHero(
          eyebrow: 'BƯỚC 1 / 3',
          title: 'Xác thực Email',
          subtitle: 'Nhập email đã đăng ký tài khoản để nhận mã OTP bảo mật.',
        ),
        const SizedBox(height: 20),
        MeowFormField(
          label: 'EMAIL',
          controller: _emailController,
          hintText: 'Nhập email đã đăng ký',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        MeowPrimaryButton(
          label: 'Gửi mã OTP',
          isLoading: _isLoading,
          onPressed: _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MeowEditorialHero(
          eyebrow: 'BƯỚC 2 / 3',
          title: 'Xác thực OTP',
          subtitle: 'Nhập mã xác thực 6 chữ số đã được gửi đến email của bạn.',
        ),
        const SizedBox(height: 20),
        MeowFormField(
          label: 'MÃ OTP',
          controller: _otpController,
          hintText: 'Nhập 6 chữ số OTP',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        MeowPrimaryButton(
          label: 'Xác nhận OTP',
          onPressed: _verifyOtp,
        ),
        const SizedBox(height: 12),
        MeowSecondaryButton(
          label: 'Quay lại nhập email',
          onPressed: () {
            _otpController.clear();
            setState(() => _step = _ChangePasswordStep.email);
          },
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MeowEditorialHero(
          eyebrow: 'BƯỚC 3 / 3',
          title: 'Đổi mật khẩu mới',
          subtitle: 'Nhập mật khẩu hiện tại và thiết lập mật khẩu mới.',
        ),
        const SizedBox(height: 20),
        MeowFormField(
          label: 'MẬT KHẨU HIỆN TẠI',
          controller: _currentPasswordController,
          hintText: '••••••••',
          obscureText: !_showCurrentPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _showCurrentPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.muted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _showCurrentPassword = !_showCurrentPassword),
          ),
        ),
        const SizedBox(height: 16),
        MeowFormField(
          label: 'MẬT KHẨU MỚI',
          controller: _newPasswordController,
          hintText: '••••••••',
          obscureText: !_showNewPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _showNewPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.muted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _showNewPassword = !_showNewPassword),
          ),
        ),
        const SizedBox(height: 16),
        MeowFormField(
          label: 'NHẬP LẠI MẬT KHẨU MỚI',
          controller: _confirmPasswordController,
          hintText: '••••••••',
          obscureText: !_showConfirmPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.muted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _showConfirmPassword = !_showConfirmPassword),
          ),
        ),
        const SizedBox(height: 22),
        MeowPrimaryButton(
          label: 'Cập nhật mật khẩu',
          isLoading: _isLoading,
          onPressed: _changePassword,
        ),
      ],
    );
  }
}

class _VerificationProgressBar extends StatelessWidget {
  final int currentStep;

  const _VerificationProgressBar({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        final active = index < currentStep;
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
            decoration: BoxDecoration(
              color: active ? AppColors.brand : AppColors.softBorder,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}
