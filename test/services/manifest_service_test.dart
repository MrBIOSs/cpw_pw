import 'dart:io';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/features/revisions/revisions.dart';

class MockDbService extends Mock implements DbService {}
class MockRsaService extends Mock implements RsaService {}

void main() {
  late ManifestService manifestService;
  late PatcherConfig  mockConfig;
  late MockDbService mockDb;
  late MockRsaService mockRsa;
  late Directory tempDir;

  setUp(() {
    mockDb = MockDbService();
    mockRsa = MockRsaService();
    tempDir = Directory.systemTemp.createTempSync('manifest_test_');

    mockConfig = PatcherConfig(
      baseDir: tempDir.path,
      dbHost: 'localhost',
      dbPort: 3306,
      dbUser: 'root',
      dbPassword: 'pwd',
      dbName: 'test_db',
      patchPath: 'patch',
      patchNewDir: 'new',
      patchCpwDir: 'cpw',
      minLauncherVer: 1,
      minPatcherVer: 1,
      minElementVer: 2,
      removeFiles: false,
      addSize: true,
    );

    when(() => mockRsa.signFile(any())).thenAnswer((_) async {});
    when(() => mockDb.initialize()).thenAnswer((_) async {});
    when(() => mockDb.dispose()).thenAnswer((_) async {});

    manifestService = ManifestService(
      config: mockConfig,
      dbService: mockDb,
      rsaService: mockRsa,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('generateManifests', () {
    test('Throws StateError if the current revision is less than the minimum revision.', () async {
      const state = (
      elementCurrentVer: 1,
      launcherCurrentVer: 1,
      patcherCurrentVer: 1,
      );

      expect(
            () => manifestService.generateManifests('element', state),
        throwsA(isA<StateError>()),
      );
    });

    test('Skips generation if the database is empty', () async {
      const state = (
      elementCurrentVer: 2,
      launcherCurrentVer: 1,
      patcherCurrentVer: 1,
      );
      final emptyResult = (affectedRows: 0, rows: <Map<String, dynamic>> []);

      when(() => mockDb.execute(any(), {'type': 'element'}))
          .thenAnswer((_) async => emptyResult);
      await manifestService.generateManifests('element', state);

      verifyNever(() => mockRsa.signFile(any()));
    });

    test('Successfully creates .md5 files, patches, and a version file.', () async {
      const state = (
      elementCurrentVer: 3,
      launcherCurrentVer: 1,
      patcherCurrentVer: 1,
      );

      final dbRows = [
        {
          'md5': 'md5_file1',
          'folder_base64': 'folder1/',
          'file_base64': 'file1.txt',
          'revision': 2,
          'added': 2,
          'size': 100,
        },
        {
          'md5': 'md5_file2',
          'folder_base64': 'folder1/',
          'file_base64': 'file2.txt',
          'revision': 3,
          'added': 2,
          'size': 200,
        }
      ];
      final QueryResult filledResult = (affectedRows: 2, rows: dbRows);

      when(() => mockDb.execute(any(), {'type': 'element'}))
          .thenAnswer((_) async => filledResult);

      final outputDirPath = mockConfig.resolvePath('${mockConfig.patchPath}/${mockConfig.patchCpwDir}/element');
      Directory(outputDirPath).createSync(recursive: true);

      await manifestService.generateManifests('element', state);

      final manifestFile = File('$outputDirPath/files.md5');
      expect(manifestFile.existsSync(), true);

      final manifestContent = manifestFile.readAsLinesSync();
      expect(manifestContent[0], '# 3');
      expect(manifestContent[1], 'md5_file1 folder1/file1.txt');
      expect(manifestContent[2], 'md5_file2 file2.txt');

      final versionFile = File('$outputDirPath/version');
      expect(versionFile.existsSync(), true);
      expect(versionFile.readAsStringSync(), '3\n');

      final patchDiff = File('$outputDirPath/v-1.inc');
      expect(patchDiff.existsSync(), true);

      final patchDiff2Lines = patchDiff.readAsLinesSync();
      expect(patchDiff2Lines[0], '# 2 3 200'); // 200 size
      expect(patchDiff2Lines[1], '!md5_file2 folder1/file2.txt'); // added(2) != revision(3) - '!'
    });

    test('Successfully cleans up old .inc files that are out of revision range', () async {
      const state = (
      elementCurrentVer: 5,
      launcherCurrentVer: 1,
      patcherCurrentVer: 1,
      );
      final dbRows = [
        {
          'md5': 'md5_file1',
          'folder_base64': 'folder1/',
          'file_base64': 'file1.txt',
          'revision': 5,
          'added': 5,
          'size': 10,
        }
      ];
      final QueryResult filledResult = (affectedRows: 1, rows: dbRows);

      when(() => mockDb.execute(any(), any())).thenAnswer((_) async => filledResult);

      final outputDirPath = mockConfig.resolvePath('${mockConfig.patchPath}/${mockConfig.patchCpwDir}/element');
      Directory(outputDirPath).createSync(recursive: true);

      final oldPatch = File('$outputDirPath/v-4.inc')..createSync();
      final validPatch = File('$outputDirPath/v-2.inc')..createSync();

      await manifestService.generateManifests('element', state);

      expect(oldPatch.existsSync(), false, reason: 'Old patch outside minRev should be removed');
      expect(validPatch.existsSync(), true, reason: 'Patch within range must remain/be overwritten');
    });
  });
}