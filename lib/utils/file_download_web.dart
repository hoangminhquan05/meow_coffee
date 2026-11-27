import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: tạo link tải tạm (Blob) rồi bấm giùm → trình duyệt tải file về thư
/// mục Tải xuống. Trả về tên file để báo cho người dùng.
Future<String> saveDownload(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  // Chờ trình duyệt bắt đầu tải rồi mới thu hồi link tạm.
  Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return '$fileName (thư mục Tải xuống)';
}
