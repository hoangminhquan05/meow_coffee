import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/firestore_paths.dart';
import '../models/order.dart';
import '../models/user_model.dart';

enum SessionEndReason { signedOut, locked, noProfile }

/// Người dùng đang đăng nhập. Lắng nghe realtime `users/{uid}`:
/// bị khóa (`is_active = false`) hoặc mất hồ sơ → đăng xuất ngay (Q14).
class SessionProvider extends ChangeNotifier {
  SessionProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  UserModel? _user;
  bool _isLoading = true;

  /// Lý do phiên vừa kết thúc (để màn đăng nhập hiển thị thông báo).
  SessionEndReason? lastEndReason;

  /// Gọi khi phiên bị kết thúc do khóa/mất hồ sơ (main.dart dùng để điều hướng).
  VoidCallback? onForcedSignOut;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  String get uid => _user?.uid ?? '';

  PersonRef get personRef => PersonRef(id: uid, name: _user?.name ?? '');

  void _onAuthChanged(User? authUser) {
    _userSub?.cancel();
    _userSub = null;
    if (authUser == null) {
      _user = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    _userSub = FirebaseFirestore.instance
        .collection(FsCollections.users)
        .doc(authUser.uid)
        .snapshots()
        .listen(
          (doc) {
            if (!doc.exists) {
              _forceSignOut(SessionEndReason.noProfile);
              return;
            }
            final user = UserModel.fromDoc(doc);
            if (!user.isActive) {
              _forceSignOut(SessionEndReason.locked);
              return;
            }
            _user = user;
            _isLoading = false;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('SessionProvider user stream error: $e');
            _forceSignOut(SessionEndReason.noProfile);
          },
        );
  }

  Future<void> _forceSignOut(SessionEndReason reason) async {
    lastEndReason = reason;
    _user = null;
    _isLoading = false;
    await FirebaseAuth.instance.signOut();
    notifyListeners();
    onForcedSignOut?.call();
  }

  Future<void> signOut() async {
    lastEndReason = SessionEndReason.signedOut;
    await FirebaseAuth.instance.signOut();
  }

  /// Chờ hồ sơ được nạp sau khi đăng nhập. Trả về lỗi (tiếng Việt) nếu không hợp lệ.
  Future<String?> waitForProfile() async {
    for (var i = 0; i < 50; i++) {
      if (_user != null) return null;
      if (!_isLoading && FirebaseAuth.instance.currentUser == null) {
        return endReasonMessage(lastEndReason) ?? 'Đăng nhập thất bại';
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return 'Không tải được thông tin tài khoản';
  }

  static String? endReasonMessage(SessionEndReason? reason) {
    switch (reason) {
      case SessionEndReason.locked:
        return 'Tài khoản đã bị khóa';
      case SessionEndReason.noProfile:
        return 'Tài khoản chưa được cấp quyền';
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
