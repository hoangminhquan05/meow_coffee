import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../services/account_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone.dart';
import '../../widgets/meow_ui.dart';
import 'register_screen.dart' show VerifyAccountArgs;

/// Xác minh tài khoản khách: ưu tiên OTP SĐT (Android/iOS/Web),
/// dự phòng link email (desktop hoặc khi gửi SMS lỗi). Cũng dùng để đổi SĐT.
class VerifyAccountScreen extends StatefulWidget {
  final VerifyAccountArgs args;

  const VerifyAccountScreen({super.key, this.args = const VerifyAccountArgs()});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  late final TextEditingController _phone;
  final _code = TextEditingController();
  PhoneOtpSession? _session;
  bool _sending = false;
  bool _confirming = false;
  int _resendIn = 0;
  Timer? _timer;

  bool _emailSent = false;
  bool _checkingEmail = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<SessionProvider>().user;
    _phone = TextEditingController(
      text: widget.args.changePhone ? '' : (user?.phone ?? ''),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendOtp() async {
    final e164 = toE164Vn(_phone.text);
    if (e164 == null) {
      _toast('SĐT di động 10 số, ví dụ 0901 234 567');
      return;
    }
    final user = context.read<SessionProvider>().user;
    if (widget.args.changePhone && user?.phoneE164 == e164 && user!.phoneVerified) {
      _toast('Đây đã là số điện thoại hiện tại của bạn');
      return;
    }
    setState(() => _sending = true);
    try {
      final session = await AccountService.sendPhoneOtp(
        e164,
        resendToken: _session?.resendToken,
        onAutoVerified: _onVerified,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _code.clear();
      });
      _startCountdown();
      _toast('Đã gửi mã OTP tới ${formatVnPhone(e164)}');
    } on AccountError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Không gửi được mã OTP: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmOtp() async {
    final session = _session;
    if (session == null) return;
    setState(() => _confirming = true);
    try {
      await AccountService.confirmPhoneOtp(session, _code.text);
      _onVerified();
    } on AccountError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Xác minh thất bại: $e');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _sendEmail() async {
    try {
      await AccountService.sendEmailVerification();
      if (!mounted) return;
      setState(() => _emailSent = true);
      _toast('Đã gửi link xác minh, hãy mở email và bấm link');
    } on AccountError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _checkEmail() async {
    setState(() => _checkingEmail = true);
    try {
      final ok = await AccountService.checkEmailVerified();
      if (!mounted) return;
      if (ok) {
        _onVerified();
      } else {
        _toast('Email chưa được xác minh, hãy bấm link trong email trước');
      }
    } catch (e) {
      _toast('Lỗi kiểm tra: $e');
    } finally {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  void _onVerified() {
    if (!mounted) return;
    _timer?.cancel();
    _toast(widget.args.changePhone
        ? 'Đã đổi số điện thoại'
        : 'Xác minh tài khoản thành công');
    _leave();
  }

  void _leave() {
    if (widget.args.afterRegister) {
      Navigator.pushNamedAndRemoveUntil(context, '/customer', (r) => false);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionProvider>().user;
    final otp = AccountService.supportsPhoneOtp;
    final change = widget.args.changePhone;
    final showPhone = change || !(user?.phoneVerified ?? false);
    final showEmail = !change && !(user?.emailVerified ?? false);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: change ? 'Đổi Số Điện Thoại' : 'Xác Minh Tài Khoản',
        showBack: !widget.args.afterRegister,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              change
                  ? 'Nhập số mới và mã OTP gửi tới số đó.'
                  : 'Xác minh để đặt đơn online. Shipper sẽ gọi số này khi giao hàng.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            // Mục nào đã xác minh thì báo xong; mục nào chưa thì cho xác minh
            // (xác minh email rồi vẫn xác minh SĐT được và ngược lại).
            if (!change && (user?.phoneVerified ?? false))
              _DoneCard(text: 'SĐT ${user!.phone} đã được xác minh'),
            if (!change && (user?.emailVerified ?? false))
              _DoneCard(text: 'Email ${user!.email} đã được xác minh'),
            if (showPhone) otp ? _buildPhoneCard() : _desktopNotice(),
            if (showPhone && showEmail)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('và / hoặc',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
            if (showEmail) _buildEmailCard(user?.email ?? ''),
            if (widget.args.afterRegister) ...[
              const SizedBox(height: 22),
              TextButton(
                onPressed: _leave,
                child: const Text('Xác minh sau, xem thực đơn trước'),
              ),
              const Text(
                'Bạn cần xác minh trước khi đặt đơn đầu tiên.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _desktopNotice() => const MeowCard(
        padding: EdgeInsets.all(16),
        child: Text(
          'Xác minh / đổi số điện thoại cần mã OTP, chỉ làm được trên app '
          'điện thoại hoặc web.',
          style: TextStyle(color: AppColors.muted),
        ),
      );

  Widget _buildPhoneCard() {
    final session = _session;
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'XÁC MINH BẰNG SỐ ĐIỆN THOẠI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            enabled: session == null && !_sending,
            decoration: const InputDecoration(
              labelText: 'Số điện thoại',
              hintText: '0901 234 567',
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          const SizedBox(height: 12),
          if (session == null)
            MeowPrimaryButton(
              label: 'Gửi mã OTP',
              icon: Icons.sms_outlined,
              isLoading: _sending,
              onPressed: _sending ? null : _sendOtp,
            )
          else ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                setState(() {});
                if (v.length == 6 && !_confirming) _confirmOtp();
              },
              decoration: const InputDecoration(
                hintText: '••••••',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            MeowPrimaryButton(
              label: 'Xác nhận mã',
              isLoading: _confirming,
              onPressed:
                  _code.text.length == 6 && !_confirming ? _confirmOtp : null,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _session = null;
                    _timer?.cancel();
                    _resendIn = 0;
                  }),
                  child: const Text('Đổi số'),
                ),
                TextButton(
                  onPressed: _resendIn > 0 || _sending ? null : _sendOtp,
                  child: Text(_resendIn > 0
                      ? 'Gửi lại sau ${_resendIn}s'
                      : 'Gửi lại mã'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailCard(String email) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Gửi link xác minh tới $email',
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkSlate),
          ),
          const SizedBox(height: 12),
          MeowSecondaryButton(
            label: _emailSent ? 'Gửi lại link' : 'Gửi link xác minh',
            icon: Icons.mark_email_unread_outlined,
            onPressed: _sendEmail,
          ),
          if (_emailSent) ...[
            const SizedBox(height: 10),
            MeowPrimaryButton(
              label: 'Tôi đã bấm link trong email',
              isLoading: _checkingEmail,
              onPressed: _checkingEmail ? null : _checkEmail,
            ),
          ],
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  final String text;

  const _DoneCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.success, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
