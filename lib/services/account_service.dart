import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../core/firestore_paths.dart';
import '../utils/phone.dart';

/// Lỗi tài khoản với thông báo tiếng Việt để hiện cho người dùng.
class AccountError implements Exception {
  final String message;
  const AccountError(this.message);
  @override
  String toString() => message;
}

/// Đăng ký khách và xác minh SĐT (OTP) / email – bước 2 kế hoạch online.
class AccountService {
  AccountService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection(FsCollections.users).doc(uid);

  /// OTP SĐT của Firebase chỉ chạy trên Android, iOS và Web.
  static bool get supportsPhoneOtp =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Tạo tài khoản khách (email + mật khẩu) và hồ sơ `users/{uid}`.
  static Future<void> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final e164 = toE164Vn(phone);
    if (e164 == null) throw const AccountError('Số điện thoại không hợp lệ');
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(name.trim());
      await _userDoc(user.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'phone': formatVnPhone(e164),
        'phone_e164': e164,
        'role': UserRole.customer.value,
        'avt_url': '',
        'is_active': true,
        'phone_verified': false,
        'email_verified': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      throw AccountError(_authMessage(e));
    }
  }

  // ---------------------------------------------------------------- OTP SĐT

  /// Gửi mã OTP tới `phone`. Trả về [PhoneOtpSession] để nhập mã.
  /// Trên Android có thể tự xác minh (đọc SMS) → gọi `onAutoVerified`.
  static Future<PhoneOtpSession> sendPhoneOtp(
    String phone, {
    VoidCallback? onAutoVerified,
    int? resendToken,
  }) async {
    final e164 = toE164Vn(phone);
    if (e164 == null) throw const AccountError('Số điện thoại không hợp lệ');
    final user = _auth.currentUser;
    if (user == null) throw const AccountError('Bạn chưa đăng nhập');

    if (kIsWeb) {
      // Web: reCAPTCHA vô hình do Firebase tự hiện. Web không có
      // updatePhoneNumber bằng mã, nên đổi số = gỡ số cũ rồi gắn số mới.
      try {
        if (_hasPhoneProvider(user)) {
          await user.unlink(PhoneAuthProvider.PROVIDER_ID);
        }
        final confirmation = await user.linkWithPhoneNumber(e164);
        return PhoneOtpSession._web(e164, confirmation);
      } on FirebaseAuthException catch (e) {
        throw AccountError(_authMessage(e));
      }
    }

    final completer = Completer<PhoneOtpSession>();
    await _auth.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Android tự đọc được SMS.
        try {
          await _applyPhoneCredential(credential, e164);
          onAutoVerified?.call();
        } catch (e) {
          debugPrint('auto phone verification failed: $e');
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(AccountError(_authMessage(e)));
        }
      },
      codeSent: (verificationId, token) {
        if (!completer.isCompleted) {
          completer.complete(PhoneOtpSession._mobile(e164, verificationId, token));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  /// Xác nhận mã OTP người dùng nhập.
  static Future<void> confirmPhoneOtp(PhoneOtpSession session, String code) async {
    final smsCode = code.trim();
    if (smsCode.length != 6) throw const AccountError('Mã OTP gồm 6 chữ số');
    try {
      final confirmation = session._confirmation;
      if (confirmation != null) {
        await confirmation.confirm(smsCode);
        await _markPhoneVerified(session.e164);
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: session._verificationId!,
          smsCode: smsCode,
        );
        await _applyPhoneCredential(credential, session.e164);
      }
    } on FirebaseAuthException catch (e) {
      throw AccountError(_authMessage(e));
    }
  }

  static bool _hasPhoneProvider(User user) =>
      user.providerData.any((p) => p.providerId == PhoneAuthProvider.PROVIDER_ID);

  /// Gắn SĐT vào tài khoản (lần đầu) hoặc thay SĐT đã gắn (đổi số).
  static Future<void> _applyPhoneCredential(
    PhoneAuthCredential credential,
    String e164,
  ) async {
    final user = _auth.currentUser!;
    if (_hasPhoneProvider(user)) {
      await user.updatePhoneNumber(credential);
    } else {
      await user.linkWithCredential(credential);
    }
    await _markPhoneVerified(e164);
  }

  /// Ghi SĐT đã xác minh vào hồ sơ. Làm mới ID token trước để Firestore
  /// Rules thấy `phone_number` mới (Rules đối chiếu với `phone_e164`).
  static Future<void> _markPhoneVerified(String e164) async {
    final user = _auth.currentUser!;
    await user.reload();
    await _auth.currentUser!.getIdToken(true);
    await _userDoc(user.uid).update({
      'phone': formatVnPhone(e164),
      'phone_e164': e164,
      'phone_verified': true,
    });
  }

  // ---------------------------------------------------------------- Email

  static Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw const AccountError('Bạn chưa đăng nhập');
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AccountError(_authMessage(e));
    }
  }

  /// Kiểm tra người dùng đã bấm link xác minh chưa; đã bấm thì ghi hồ sơ.
  static Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final fresh = _auth.currentUser!;
    if (!fresh.emailVerified) return false;
    await fresh.getIdToken(true);
    await _userDoc(fresh.uid).update({'email_verified': true});
    return true;
  }

  // ---------------------------------------------------------------- Lỗi

  static String _authMessage(FirebaseAuthException e) {
    // Firebase chỉ gửi SMS thật khi project ở gói Blaze (đã gắn thanh toán).
    if ((e.message ?? '').contains('BILLING_NOT_ENABLED')) {
      return 'Firebase chưa bật thanh toán (gói Blaze) nên chưa gửi được SMS. '
          'Hãy xác minh bằng email.';
    }
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email này đã có tài khoản';
      case 'invalid-email':
        return 'Email không hợp lệ';
      case 'weak-password':
        return 'Mật khẩu quá yếu (ít nhất 6 ký tự)';
      case 'invalid-phone-number':
        return 'Số điện thoại không hợp lệ';
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'Số điện thoại này đã được dùng cho tài khoản khác';
      case 'invalid-verification-code':
        return 'Mã OTP không đúng';
      case 'session-expired':
      case 'code-expired':
        return 'Mã OTP đã hết hạn, vui lòng gửi lại';
      case 'too-many-requests':
        return 'Bạn thao tác quá nhiều lần, vui lòng thử lại sau';
      case 'quota-exceeded':
        return 'Đã hết lượt gửi SMS hôm nay, hãy xác minh bằng email';
      case 'operation-not-allowed':
        // Phone chưa bật, hoặc chính sách vùng SMS chưa cho phép Việt Nam.
        return 'Firebase chưa cho gửi SMS tới số này (kiểm tra Phone và '
            'chính sách vùng SMS trong Authentication)';
      case 'requires-recent-login':
        return 'Vui lòng đăng nhập lại rồi thử lại';
      case 'network-request-failed':
        return 'Lỗi mạng, vui lòng kiểm tra kết nối';
      default:
        return e.message ?? 'Đã có lỗi xảy ra (${e.code})';
    }
  }
}

/// Phiên chờ nhập OTP (mobile: verificationId; web: ConfirmationResult).
class PhoneOtpSession {
  final String e164;
  final String? _verificationId;
  final int? resendToken;
  final ConfirmationResult? _confirmation;

  PhoneOtpSession._mobile(this.e164, this._verificationId, this.resendToken)
      : _confirmation = null;

  PhoneOtpSession._web(this.e164, this._confirmation)
      : _verificationId = null,
        resendToken = null;
}
