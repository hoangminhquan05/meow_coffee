import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Chuông + rung báo đơn mới / lời mời giao đơn. flutter_ringtone_player chỉ
/// có trên Android/iOS – chạy web/Windows (thử nhiều tài khoản cùng lúc) thì
/// bỏ qua thay vì báo lỗi.
class AlertSound {
  AlertSound._();

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void _safe(Future<void> Function() call) {
    if (!_supported) return;
    call().catchError((Object e) => debugPrint('AlertSound: $e'));
  }

  /// Một tiếng thông báo (đơn mới cho NV).
  static void notify() {
    _safe(() => FlutterRingtonePlayer().playNotification());
    HapticFeedback.vibrate();
  }

  /// Chuông lặp cho tới khi gọi [stop] (lời mời shipper).
  static void ringLoop() => _safe(() => FlutterRingtonePlayer().playRingtone(looping: true));

  static void stop() => _safe(() => FlutterRingtonePlayer().stop());
}
