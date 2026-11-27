import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _downloadsChannel = MethodChannel('com.example.meow_coffee/downloads');

/// Android: lưu vào Downloads qua MainActivity. Nơi khác (hoặc Android lưu
/// không được): thư mục Downloads, không có thì Documents của app.
/// Trả về đường dẫn file.
Future<String> saveDownload(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  if (Platform.isAndroid) {
    final savedPath = await _downloadsChannel.invokeMethod<String>(
      'saveToDownloads',
      {'fileName': fileName, 'mimeType': mimeType, 'bytes': bytes},
    );
    if (savedPath != null && savedPath.isNotEmpty) return savedPath;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  return file.path;
}
