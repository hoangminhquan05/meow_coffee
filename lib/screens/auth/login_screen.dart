import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  String? _emailError;
  String? _passwordError;
  bool _isButtonPressed = false;
  bool _isLoading = false;

  static final _emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isButtonPressed = true;
      _emailError = null;
      _passwordError = null;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _isButtonPressed = false);
      }
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      setState(() => _emailError = 'Vui lòng nhập email!');
      return;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = 'Vui lòng nhập mật khẩu!');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _emailError = 'Vui lòng nhập email hợp lệ!');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (credential.user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('☕ Đăng nhập thành công!')),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          message = 'Email hoặc mật khẩu không đúng!';
          break;
        case 'email-already-in-use':
          message = 'Tài khoản đã tồn tại!';
          break;
        default:
          message = 'Lỗi đăng nhập: ${e.message ?? e.code}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng nhập thất bại!')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.mutedPurple.withValues(alpha: 0.8)),
      prefixIcon: Icon(icon, color: AppColors.mutedPurple),
      errorText: errorText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppColors.mutedPurple.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.mutedPurple,
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/background_login.jpg',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.white.withValues(alpha: 0.2)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.mutedPurple, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x806E3C1B),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: _isButtonPressed ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Image.asset(
                        'assets/images/coffee_login.png',
                        width: 120,
                        height: 120,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Meow Coffee',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        color: AppColors.mutedPurple,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Đăng nhập để khám phá thế giới cà phê',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      cursorColor: AppColors.mutedPurple,
                      onChanged: (_) {
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                      },
                      decoration: _inputDecoration(
                        label: 'Email',
                        icon: Icons.email,
                        errorText: _emailError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      cursorColor: AppColors.mutedPurple,
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                      onSubmitted: (_) => _handleLogin(),
                      decoration: _inputDecoration(
                        label: 'Mật khẩu',
                        icon: Icons.lock,
                        errorText: _passwordError,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedScale(
                      scale: _isButtonPressed ? 0.95 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.softPurple,
                                AppColors.mutedPurple,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'ĐĂNG NHẬP',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => Navigator.pushNamed(context, '/forgot_pass'),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Quên mật khẩu?',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
