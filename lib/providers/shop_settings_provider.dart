import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/firestore_paths.dart';
import '../models/order.dart';
import '../models/shop_settings.dart';

/// Lắng nghe realtime `settings/shop`. Chưa có doc → dùng giá trị mặc định.
/// Chỉ lắng nghe khi đã đăng nhập (Rules yêu cầu tài khoản đang hoạt động).
class ShopSettingsProvider extends ChangeNotifier {
  static DocumentReference<Map<String, dynamic>> get docRef =>
      FirebaseFirestore.instance.collection(FsCollections.settings).doc('shop');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  ShopSettings _settings = ShopSettings.defaults;
  bool _exists = false;
  bool _loaded = false;
  Object? _error;

  ShopSettings get settings => _settings;

  /// Doc `settings/shop` đã được tạo chưa (admin bấm Lưu lần đầu).
  bool get exists => _exists;
  bool get isLoaded => _loaded;
  Object? get error => _error;

  /// Gọi khi đăng nhập (true) / đăng xuất (false). Chạy sau frame hiện tại
  /// vì được gọi từ ProxyProvider.update (đang build).
  void setActive(bool active) => scheduleMicrotask(() => _setActive(active));

  void _setActive(bool active) {
    if (active && _sub == null) {
      _sub = docRef.snapshots().listen(
        (doc) {
          _exists = doc.exists;
          _settings = doc.exists
              ? ShopSettings.fromMap(doc.data()!)
              : ShopSettings.defaults;
          _loaded = true;
          _error = null;
          notifyListeners();
        },
        onError: (Object e) {
          debugPrint('ShopSettingsProvider error: $e');
          _error = e;
          _loaded = true;
          notifyListeners();
        },
      );
    } else if (!active && _sub != null) {
      _sub!.cancel();
      _sub = null;
      _settings = ShopSettings.defaults;
      _exists = false;
      _loaded = false;
      notifyListeners();
    }
  }

  /// Admin lưu toàn bộ cài đặt.
  static Future<void> save(ShopSettings s, PersonRef by) => docRef.set({
        ...s.toMap(),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': by.toMap(),
      }, SetOptions(merge: true));

  /// NV/admin bật/tắt tạm ngưng nhận đơn online (có hiệu lực ngay).
  static Future<void> setOnlinePaused(bool paused, PersonRef by) => docRef.set({
        'online_paused': paused,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': by.toMap(),
      }, SetOptions(merge: true));

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
