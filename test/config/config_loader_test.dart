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
    if (await tempDir.exists()) {
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

      expect(config.dbUser, 'admin');
      expect(config.dbHost, 'localhost');
      expect(config.removeFolders, isTrue);
      expect(config.minLauncherVer, 1);
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
        remove-folders = no
        remove-files = 1
        add-size = false
      ''');

      final config = await ConfigLoader.load(configPath: configFile.path);
      expect(config.removeFolders, isFalse); // 'no' == false
      expect(config.removeFiles, isTrue);    // '1' == true
      expect(config.addSize, isFalse);       // 'false' == false
    });
  });
}
