import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_coffee/config/env_config.dart';

void main() {
  test('no hard-coded defaults: missing .env key names the key', () {
    dotenv.testLoad(fileInput: 'CLOUDINARY_FOLDER_CHAT=meow_coffee/chats\n');
    expect(EnvConfig.cloudinaryFolderChat, 'meow_coffee/chats');
    expect(
      () => EnvConfig.vietQrAccountNumber,
      throwsA(isA<MissingEnvError>()
          .having((e) => e.toString(), 'message', 'Thiếu VIETQR_ACCOUNT_NUMBER trong file .env')),
    );
    expect(() => EnvConfig.cloudinaryFolderProducts, throwsStateError);
  });
}
