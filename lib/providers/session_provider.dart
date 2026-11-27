import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../core/route_guard.dart' as route_guard;
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

  /// Hoàn tất khi Firebase báo trạng thái đăng nhập lần đầu (phiên cũ còn
  /// hay không) – màn khởi động chờ cái này.
  final Completer<void> _authReady = Completer<void>();

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

  bool get isCustomer => _user?.role == UserRole.customer;
  bool get isShipper => _user?.role == UserRole.shipper;

  /// Nhân viên hoặc admin: bán tại quầy và xử lý đơn online.
  bool get isSeller =>
      _user?.role == UserRole.staff || _user?.role == UserRole.admin;

  /// Màn chính theo vai trò.
  String get homeRoute => homeRouteFor(_user?.role);

  static String homeRouteFor(UserRole? role) => route_guard.homeRouteFor(role);

  void _onAuthChanged(User? authUser) {
    if (!_authReady.isCompleted) _authReady.complete();
    _userSub?.cancel();
    _userSub = null;
    // Đổi sang tài khoản khác: bỏ ngay hồ sơ cũ để không ai đọc nhầm vai trò
    // của người trước (trước đây đăng nhập shipper sau phiên NV còn sót lại
    // → bị đưa vào trang chủ NV).
    if (_user != null && _user!.uid != authUser?.uid) _user = null;
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
              // Khách vừa đăng ký: hồ sơ được ghi ngay sau khi tạo tài khoản
              // Auth, nên chờ thêm thay vì đăng xuất (snapshot sẽ báo lại).
              final created = authUser.metadata.creationTime;
              final justCreated = created != null &&
                  DateTime.now().difference(created) <
                      const Duration(seconds: 30);
              if (justCreated) return;
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

  /// Chờ nạp hồ sơ `users/{uid}` của đúng tài khoản `uid` (mặc định: tài
  /// khoản Firebase hiện tại). Trả về lỗi (tiếng Việt) nếu không hợp lệ.
  Future<String?> waitForProfile({String? uid, Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = FirebaseAuth.instance.currentUser;
      final expected = uid ?? current?.uid;
      if (expected != null && _user?.uid == expected) return null;
      if (current == null || (uid != null && current.uid != uid)) {
        // Bị đăng xuất (khóa / chưa cấp quyền) hoặc đã đổi sang tài khoản khác.
        if (!_isLoading || current != null) {
          return endReasonMessage(lastEndReason) ?? 'Đăng nhập thất bại';
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return 'Không tải được thông tin tài khoản';
  }

  /// Màn đầu tiên khi mở app (kể cả F5 trên web): còn phiên đăng nhập hợp lệ
  /// → trang chủ đúng vai trò; không thì màn đăng nhập.
  Future<String> startRoute() async {
    try {
      await _authReady.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return '/login';
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '/login';
    final error = await waitForProfile(uid: uid, timeout: const Duration(seconds: 15));
    return error == null ? homeRoute : '/login';
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
