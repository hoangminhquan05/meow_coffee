import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

web.HTMLAudioElement? _loop;

web.HTMLAudioElement _audio(String asset) =>
    web.HTMLAudioElement()..src = ui_web.assetManager.getAssetUrl(asset);

/// Trình duyệt chặn tự phát tiếng khi người dùng chưa bấm gì trên trang
/// (vd. vừa F5) – khi đó bỏ qua, chỉ ghi log.
void _play(web.HTMLAudioElement audio) {
  audio.play().toDart.catchError((Object e) {
    debugPrint('Âm báo web bị chặn: $e');
    return null;
  });
}

void webPlayOnce(String asset) => _play(_audio(asset));

void webStartLoop(String asset) {
  webStopLoop();
  final audio = _audio(asset)..loop = true;
  _loop = audio;
  _play(audio);
}

void webStopLoop() {
  final audio = _loop;
  _loop = null;
  if (audio == null) return;
  audio.pause();
  audio.currentTime = 0;
}
