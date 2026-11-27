/// Lưu file do app tạo ra (hóa đơn PDF…) theo từng nền tảng:
/// - Web: trình duyệt tải file về thư mục Tải xuống.
/// - Android: thư mục Downloads (qua MainActivity).
/// - Nơi khác (iOS, desktop): thư mục Downloads/Documents của app.
///
/// `saveDownload(bytes, fileName:, mimeType:)` trả về chỗ đã lưu để báo cho
/// người dùng.
library;

export 'file_download_io.dart' if (dart.library.js_interop) 'file_download_web.dart';
