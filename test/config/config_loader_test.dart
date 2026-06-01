import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/config.dart';

void main() {
  late Directory tempDir;
  late File configFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('patcher_test_');
    configFile = File(path.join(tempDir.path, 'patcher.conf'));
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ConfigLoader.load', () {
    test('should load valid config file and use default values', () async {
      await configFile.writeAsString('''
        db-user=admin
        db-password=secret
        db-name=patcher_db
      ''');

      final config = await ConfigLoader.load(configPath: configFile.path);

      // Checking required fields
      expect(config.dbUser, equals('admin'));
      expect(config.dbPassword, equals('secret'));
      expect(config.dbName, equals('patcher_db'));

      // Checking default values
      expect(config.dbHost, equals('localhost'));
      expect(config.dbPort, equals(3306));
      expect(config.patchPath, equals('files'));
      expect(config.patchNewDir, equals('new'));
      expect(config.patchCpwDir, equals('CPW'));
      expect(config.minLauncherVer, equals(1));
      expect(config.minPatcherVer, equals(1));
      expect(config.minElementVer, equals(1));
      expect(config.removeFiles, isTrue);
      expect(config.addSize, isTrue);
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
        min-element-ver=not_a_number
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
      await configFile.writeAsString('''
        db-user = u
        db-password = p
        db-name = n
        remove-input-files = 1
        add-file-size-to-inc = false
      ''');

      final config = await ConfigLoader.load(configPath: configFile.path);
      expect(config.removeFiles, isTrue);    // '1' == true
      expect(config.addSize, isFalse);       // 'false' == false
    });

    test('Выбрасывает FormatException при передаче невалидного булева флага', () async {
      await configFile.writeAsString('''
        db-user = admin
        db-password = 123
        db-name = db
        remove-input-files = maybe
      ''');

      expect(
            () => ConfigLoader.load(configPath: configFile.path),
        throwsA(isA<FormatException>().having(
              (e) => e.message,
          'message',
          contains('Expected boolean, got "maybe"'),
        )),
      );
    });
  });
}
