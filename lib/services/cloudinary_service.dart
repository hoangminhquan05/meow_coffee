import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/env_config.dart';

class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  String get cloudName => EnvConfig.cloudinaryCloudName;
  String get apiKey => EnvConfig.cloudinaryApiKey;
  String get apiSecret => EnvConfig.cloudinaryApiSecret;

  bool get isConfigured =>
      cloudName.isNotEmpty && apiKey.isNotEmpty && apiSecret.isNotEmpty;

  String _generateSignature(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final toSign = sortedKeys.map((k) => '$k=${params[k]}').join('&');
    return sha1.convert(utf8.encode('$toSign$apiSecret')).toString();
  }

  Future<String> uploadImage(
    File file, {
    String? folder,
    String? publicId,
  }) async {
    final targetFolder = (folder != null && folder.isNotEmpty)
        ? folder
        : EnvConfig.cloudinaryFolderDefault;
    if (!isConfigured) {
      throw StateError(
        'Cloudinary chưa được cấu hình. Hãy điền CLOUDINARY_CLOUD_NAME, '
        'CLOUDINARY_API_KEY và CLOUDINARY_API_SECRET trong file .env.',
      );
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signParams = <String, String>{
      'folder': targetFolder,
      'timestamp': timestamp,
      if (publicId != null && publicId.isNotEmpty) 'public_id': publicId,
    };
    final signature = _generateSignature(signParams);

    final baseUrl = EnvConfig.cloudinaryApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(
      '$baseUrl/$cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['folder'] = targetFolder
      ..fields['signature'] = signature;

    if (publicId != null && publicId.isNotEmpty) {
      request.fields['public_id'] = publicId;
    }

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload thất bại: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = data['secure_url'] as String?;
    if (secureUrl != null && secureUrl.isNotEmpty) {
      return secureUrl;
    }
    final url = data['url'] as String? ?? '';
    return url.replaceFirst('http://', 'https://');
  }

  Future<void> deleteImageByUrl(String imageUrl) async {
    if (!isConfigured || !imageUrl.contains('/upload/')) return;

    final afterUpload = imageUrl.split('/upload/').last;
    final slashIndex = afterUpload.indexOf('/');
    final withoutVersion =
        slashIndex >= 0 ? afterUpload.substring(slashIndex + 1) : afterUpload;
    final dotIndex = withoutVersion.lastIndexOf('.');
    final publicId =
        dotIndex >= 0 ? withoutVersion.substring(0, dotIndex) : withoutVersion;

    if (publicId.isEmpty) return;

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signParams = <String, String>{
      'invalidate': 'true',
      'public_id': publicId,
      'timestamp': timestamp,
    };
    final signature = _generateSignature(signParams);

    final baseUrl = EnvConfig.cloudinaryApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(
      '$baseUrl/$cloudName/image/destroy',
    );
    await http.post(
      uri,
      body: {
        'public_id': publicId,
        'invalidate': 'true',
        'api_key': apiKey,
        'timestamp': timestamp,
        'signature': signature,
      },
    );
  }
}
