import '../config/env_config.dart';

/// Link ảnh mã VietQR (api.vietqr.io) đã điền sẵn số tiền + nội dung chuyển khoản.
String buildVietQrUrl({required int amount, required String content}) {
  final base = EnvConfig.vietQrApiBaseUrl.replaceAll(RegExp(r'/$'), '');
  return '$base/${EnvConfig.vietQrBankBin}-${EnvConfig.vietQrAccountNumber}'
      '-${EnvConfig.vietQrTemplateId}.jpg'
      '?accountName=${Uri.encodeComponent(EnvConfig.vietQrAccountName)}'
      '&amount=$amount&addInfo=${Uri.encodeComponent(content)}';
}
