import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../services/account_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone.dart';
import '../../widgets/meow_ui.dart';

/// Khách đăng ký tài khoản: tên, email, SĐT, mật khẩu (O2).
/// Xong chuyển sang xác minh SĐT/email (có thể bỏ qua).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  final Map<String, String?> _errors = {};

  static final _emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$');

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    final e = <String, String?>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Vui lòng nhập họ tên';
    if (!_emailRegex.hasMatch(_email.text.trim())) {
      e['email'] = 'Email không hợp lệ';
    }
    if (toE164Vn(_phone.text) == null) {
      e['phone'] = 'SĐT di động 10 số, ví dụ 0901 234 567';
    }
    if (_password.text.length < 6) e['password'] = 'Mật khẩu ít nhất 6 ký tự';
    if (_confirm.text != _password.text) e['confirm'] = 'Mật khẩu nhập lại không khớp';
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    try {
      await AccountService.registerCustomer(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
      );
      if (!mounted) return;
      final error = await context.read<SessionProvider>().waitForProfile();
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        setState(() => _loading = false);
        return;
      }
      // Đăng ký xong → xác minh ngay (có nút "Xác minh sau").
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/verify_account',
        (route) => false,
        arguments: const VerifyAccountArgs(afterRegister: true),
      );
    } on AccountError catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Đăng ký thất bại: $e')));
    }
  }

  Widget _input(
    String key,
    String label,
    TextEditingController c, {
    String? hint,
    TextInputType? keyboard,
    bool password = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: password && _obscure,
            enabled: !_loading,
            onChanged: (_) {
              if (_errors[key] != null) setState(() => _errors[key] = null);
            },
            decoration: InputDecoration(
              hintText: hint,
              errorText: _errors[key],
              suffixIcon: password
                  ? IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppColors.muted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Đăng Ký'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MeowEditorialHero(
                eyebrow: 'MEOW COFFEE',
                title: 'Tạo tài khoản',
                subtitle: 'Đặt món online, giao tận nơi.',
              ),
              const SizedBox(height: 20),
              _input('name', 'HỌ TÊN', _name, hint: 'Nguyễn Văn A'),
              _input('email', 'EMAIL', _email,
                  hint: 'ban@example.com', keyboard: TextInputType.emailAddress),
              _input('phone', 'SỐ ĐIỆN THOẠI', _phone,
                  hint: '0901 234 567', keyboard: TextInputType.phone),
              _input('password', 'MẬT KHẨU', _password,
                  hint: 'Ít nhất 6 ký tự', password: true),
              _input('confirm', 'NHẬP LẠI MẬT KHẨU', _confirm, password: true),
              const SizedBox(height: 8),
              MeowPrimaryButton(
                label: 'Đăng ký',
                isLoading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: const Text('Đã có tài khoản? Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tham số cho màn xác minh.
class VerifyAccountArgs {
  /// Vừa đăng ký xong (hiện nút "Xác minh sau").
  final bool afterRegister;

  /// Đổi SĐT: xác minh số mới thay vì số trong hồ sơ.
  final bool changePhone;

  const VerifyAccountArgs({this.afterRegister = false, this.changePhone = false});
}
