import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Xem trước ảnh vừa chọn bằng image_picker – chạy được cả điện thoại lẫn web
/// (web không có Image.file; đường dẫn XFile trên web là blob URL).
class PickedImage extends StatelessWidget {
  final XFile file;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const PickedImage({
    super.key,
    required this.file,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) => kIsWeb
      ? Image.network(file.path,
          fit: fit, width: width, height: height, errorBuilder: errorBuilder)
      : Image.file(File(file.path),
          fit: fit, width: width, height: height, errorBuilder: errorBuilder);
}
