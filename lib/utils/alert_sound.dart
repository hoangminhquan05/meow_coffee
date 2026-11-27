import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'web_sound.dart';

/// Chuông + rung báo đơn mới / lời mời giao đơn / tin nhắn mới.
/// - Android/iOS: chuông hệ thống (flutter_ringtone_player).
/// - Web: file trong assets/sounds/ (trình duyệt chỉ cho phát tiếng sau khi
///   người dùng đã bấm vào trang ít nhất một lần). Rung chạy trên Chrome Android.
/// - Windows/macOS/Linux: bỏ qua thay vì báo lỗi.
class AlertSound {
  AlertSound._();

  static const _notifyAsset = 'assets/sounds/notify.wav';
  static const _ringAsset = 'assets/sounds/ring.wav';

  static bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void _safe(Future<void> Function() call) {
    if (!_mobile) return;
    call().catchError((Object e) => debugPrint('AlertSound: $e'));
  }

  /// Một tiếng thông báo (đơn mới cho NV, tin nhắn mới).
  static void notify() {
    if (kIsWeb) {
      webPlayOnce(_notifyAsset);
    } else {
      _safe(() => FlutterRingtonePlayer().playNotification());
    }
    HapticFeedback.vibrate();
  }

  /// Chuông lặp cho tới khi gọi [stop] (lời mời shipper).
  static void ringLoop() {
    if (kIsWeb) {
      webStartLoop(_ringAsset);
    } else {
      _safe(() => FlutterRingtonePlayer().playRingtone(looping: true));
    }
  }

  static void stop() {
    if (kIsWeb) {
      webStopLoop();
    } else {
      _safe(() => FlutterRingtonePlayer().stop());
    }
  }
}
