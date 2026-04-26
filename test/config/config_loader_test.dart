import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/config_loader.dart';

void main() {
  late Directory tempDir;
  late File configFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('patcher_test_');
    configFile = File(path.join(tempDir.path, 'patcher.conf'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ConfigLoader.load', () {
    test('should load valid config file and use default values', () async {
      await configFile.writeAsString('''
        rsa-private-key=private_key_data
        rsa-public-key=public_key_data
        rsa-modus=123456789
        rsa-private-x=987654321
        rsa-public-x=65537
        db-user=admin
        db-password=secret
        db-name=patcher_db
      ''');

      final config = await ConfigLoader.load(configPath: configFile.path);

      expect(config.rsaPrivateKey, 'private_key_data');
      expect(config.dbHost, 'localhost');
      expect(config.removeFolders, isTrue);
      expect(config.rsaModulus, BigInt.from(123456789));
    });

    test('should throw StateError if required field is missing', () async {
      await configFile.writeAsString('db-user=admin');

      expect(
            () => ConfigLoader.load(configPath: configFile.path),
        throwsStateError,
      );
    });

    test('should throw FormatException on invalid types', () async {
      await configFile.writeAsString('''
        rsa-private-key=key
        rsa-public-key=key
        rsa-modus=not_a_number
        db-user=admin
        db-password=pass
        db-name=db
      ''');

      expect(
            () => ConfigLoader.load(configPath: configFile.path),
        throwsFormatException,
      );
    });
  });

  group('ConfigLoader logic (_buildAndValidate)', () {
    test('parseBool should handle various formats', () async {
      final baseConfig = {
        'rsa-private-key': 'k', 'rsa-public-key': 'k',
        'rsa-modus': '1', 'rsa-private-x': '1', 'rsa-public-x': '1',
        'db-user': 'u', 'db-password': 'p', 'db-name': 'd',
      };

      await configFile.writeAsString('''
        ${baseConfig.entries.map((e) => "${e.key}=${e.value}").join('\n')}
        remove-folders=yes
        remove-files=0
      ''');

      final config = await ConfigLoader.load(configPath: configFile.path);
      expect(config.removeFolders, isTrue); // 'yes' = true
      expect(config.removeFiles, isFalse);  // '0' = false
    });
  });
}
