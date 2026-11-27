import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static String _get(String key, {String fallback = ''}) {
    final value = dotenv.isInitialized ? dotenv.env[key]?.trim() : null;
    if (value != null && value.isNotEmpty) return value;
    return fallback;
  }

  /// Cấu hình bắt buộc: lấy từ `.env` (hoặc --dart-define), không có giá trị
  /// mặc định trong code. Thiếu thì báo lỗi rõ tên khóa lúc dùng tới.
  static String _require(String key, {String fallback = ''}) {
    final value = _get(key, fallback: fallback);
    if (value.isEmpty) throw MissingEnvError(key);
    return value;
  }

  // Firebase
  /// API key của app Android (dùng mặc định cho nền tảng khác nếu thiếu key riêng).
  static String get firebaseApiKey => _get(
        'FIREBASE_API_KEY',
        fallback: const String.fromEnvironment('FIREBASE_API_KEY'),
      );

  static String get firebaseIosApiKey => _get(
        'FIREBASE_IOS_API_KEY',
        fallback: const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
      );

  static String get firebaseWebApiKey => _get(
        'FIREBASE_WEB_API_KEY',
        fallback: const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
      );

  static String get firebaseWebAppId => _get(
        'FIREBASE_WEB_APP_ID',
        fallback: const String.fromEnvironment('FIREBASE_WEB_APP_ID'),
      );

  static String get firebaseAuthDomain => _get(
        'FIREBASE_AUTH_DOMAIN',
        fallback: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      );

  static String get firebaseProjectId => _get(
        'FIREBASE_PROJECT_ID',
        fallback: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      );

  static String get firebaseMessagingSenderId => _get(
        'FIREBASE_MESSAGING_SENDER_ID',
        fallback: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      );

  static String get firebaseStorageBucket => _get(
        'FIREBASE_STORAGE_BUCKET',
        fallback: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      );

  static String get firebaseAndroidAppId => _get(
        'FIREBASE_ANDROID_APP_ID',
        fallback: const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
      );

  static String get firebaseIosAppId => _get(
        'FIREBASE_IOS_APP_ID',
        fallback: const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
      );

  static String get firebaseIosBundleId => _get(
        'FIREBASE_IOS_BUNDLE_ID',
        fallback: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
      );

  /// Cloudflare Worker – API bán online, ví dụ `https://meow-coffee-api.ten.workers.dev`.
  static String get orderApiBaseUrl => _get(
        'ORDER_API_BASE_URL',
        fallback: const String.fromEnvironment('ORDER_API_BASE_URL'),
      );

  /// Thử OTP bằng số test của Firebase (bỏ reCAPTCHA), chỉ có tác dụng ở bản debug.
  static bool get authPhoneTestMode =>
      _get('AUTH_PHONE_TEST_MODE').toLowerCase() == 'true';

  static String _or(String value, String fallback) =>
      value.isNotEmpty ? value : fallback;

  /// Android → app Android; iOS/macOS → app iOS; Web/Windows/Linux → app Web.
  static FirebaseOptions? get firebaseOptions {
    if (firebaseProjectId.isEmpty) return null;

    var apiKey = firebaseApiKey;
    var appId = firebaseAndroidAppId;
    String? authDomain;
    String? iosBundleId;

    final isWebLike = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final isApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (isWebLike) {
      apiKey = _or(firebaseWebApiKey, apiKey);
      appId = _or(firebaseWebAppId, appId);
      authDomain = firebaseAuthDomain.isEmpty ? null : firebaseAuthDomain;
    } else if (isApple) {
      apiKey = _or(firebaseIosApiKey, apiKey);
      appId = _or(firebaseIosAppId, appId);
      iosBundleId = firebaseIosBundleId.isEmpty ? null : firebaseIosBundleId;
    }

    if (apiKey.isEmpty || appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      authDomain: authDomain,
      storageBucket: firebaseStorageBucket.isEmpty ? null : firebaseStorageBucket,
      iosBundleId: iosBundleId,
    );
  }

  // Cloudinary
  static String get cloudinaryCloudName => _get(
        'CLOUDINARY_CLOUD_NAME',
        fallback: const String.fromEnvironment('CLOUDINARY_CLOUD_NAME'),
      );

  static String get cloudinaryApiKey => _get(
        'CLOUDINARY_API_KEY',
        fallback: const String.fromEnvironment('CLOUDINARY_API_KEY'),
      );

  static String get cloudinaryApiSecret => _get(
        'CLOUDINARY_API_SECRET',
        fallback: const String.fromEnvironment('CLOUDINARY_API_SECRET'),
      );

  static String get cloudinaryApiBaseUrl => _require(
        'CLOUDINARY_API_BASE_URL',
        fallback: const String.fromEnvironment('CLOUDINARY_API_BASE_URL'),
      );

  static String get cloudinaryFolderDefault => _require(
        'CLOUDINARY_FOLDER_DEFAULT',
        fallback: const String.fromEnvironment('CLOUDINARY_FOLDER_DEFAULT'),
      );

  static String get cloudinaryFolderProducts => _require(
        'CLOUDINARY_FOLDER_PRODUCTS',
        fallback: const String.fromEnvironment('CLOUDINARY_FOLDER_PRODUCTS'),
      );

  static String get cloudinaryFolderBanners => _require(
        'CLOUDINARY_FOLDER_BANNERS',
        fallback: const String.fromEnvironment('CLOUDINARY_FOLDER_BANNERS'),
      );

  static String get cloudinaryFolderAvatars => _require(
        'CLOUDINARY_FOLDER_AVATARS',
        fallback: const String.fromEnvironment('CLOUDINARY_FOLDER_AVATARS'),
      );

  static String get cloudinaryFolderChat => _require(
        'CLOUDINARY_FOLDER_CHAT',
        fallback: const String.fromEnvironment('CLOUDINARY_FOLDER_CHAT'),
      );

  // EmailJS
  static String get emailJsApiUrl => _require(
        'EMAILJS_API_URL',
        fallback: const String.fromEnvironment('EMAILJS_API_URL'),
      );

  static String get emailJsOrigin => _require(
        'EMAILJS_ORIGIN',
        fallback: const String.fromEnvironment('EMAILJS_ORIGIN'),
      );

  static String get emailJsServiceId => _get(
        'EMAILJS_SERVICE_ID',
        fallback: const String.fromEnvironment('EMAILJS_SERVICE_ID'),
      );

  static String get emailJsOtpTemplateId => _get(
        'EMAILJS_OTP_TEMPLATE_ID',
        fallback: const String.fromEnvironment('EMAILJS_OTP_TEMPLATE_ID'),
      );

  static String get emailJsWelcomeTemplateId => _get(
        'EMAILJS_WELCOME_TEMPLATE_ID',
        fallback: const String.fromEnvironment('EMAILJS_WELCOME_TEMPLATE_ID'),
      );

  static String get emailJsPublicKey => _get(
        'EMAILJS_PUBLIC_KEY',
        fallback: const String.fromEnvironment('EMAILJS_PUBLIC_KEY'),
      );

  static String get emailJsPrivateKey => _get(
        'EMAILJS_PRIVATE_KEY',
        fallback: const String.fromEnvironment('EMAILJS_PRIVATE_KEY'),
      );

  // VietQR
  static String get vietQrApiBaseUrl => _require(
        'VIETQR_API_BASE_URL',
        fallback: const String.fromEnvironment('VIETQR_API_BASE_URL'),
      );

  static String get vietQrBankBin => _require(
        'VIETQR_BANK_BIN',
        fallback: const String.fromEnvironment('VIETQR_BANK_BIN'),
      );

  static String get vietQrAccountNumber => _require(
        'VIETQR_ACCOUNT_NUMBER',
        fallback: const String.fromEnvironment('VIETQR_ACCOUNT_NUMBER'),
      );

  static String get vietQrAccountName => _require(
        'VIETQR_ACCOUNT_NAME',
        fallback: const String.fromEnvironment('VIETQR_ACCOUNT_NAME'),
      );

  static String get vietQrTemplateId => _require(
        'VIETQR_TEMPLATE_ID',
        fallback: const String.fromEnvironment('VIETQR_TEMPLATE_ID'),
      );
}

/// Thiếu một khóa cấu hình trong `.env`.
class MissingEnvError extends StateError {
  final String key;

  MissingEnvError(this.key) : super('Thiếu $key trong file .env');

  @override
  String toString() => message;
}
