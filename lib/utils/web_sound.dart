/// Phát âm thanh trong assets trên bản web (thẻ <audio> của trình duyệt).
/// Nền tảng khác: không làm gì – Android/iOS dùng chuông hệ thống
/// (flutter_ringtone_player) trong AlertSound.
///
/// - `webPlayOnce(asset)`: phát một lần.
/// - `webStartLoop(asset)` / `webStopLoop()`: phát lặp tới khi dừng.
library;

export 'web_sound_stub.dart' if (dart.library.js_interop) 'web_sound_web.dart';
