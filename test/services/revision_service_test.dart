import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/features/revisions/revisions.dart';
import 'package:cpw_pw/config/config.dart';

class MockPackerService extends Mock implements PackerService {}
class MockDbService extends Mock implements DbService {}

void main() {
  late RevisionService revisionService;
  late PatcherConfig mockConfig;
  late MockPackerService mockPacker;
  late MockDbService mockDb;
  late Directory tempDir;

  setUp(() {
    mockPacker = MockPackerService();
    mockDb = MockDbService();
    tempDir = Directory.systemTemp.createTempSync('revision_test_');
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
      minLauncherVer: 10,
      minPatcherVer: 20,
      minElementVer: 30,
      removeFiles: true,
      addSize: true,
    );

    for (final type in ['element', 'launcher', 'patcher']) {
      Directory(path.join(tempDir.path, 'patch', 'cpw', type))
          .createSync(recursive: true);
    }

    registerFallbackValue(File(''));

    when(() => mockDb.initialize()).thenAnswer((_) async {});
    when(() => mockDb.dispose()).thenAnswer((_) async {});
    when(() => mockPacker.pack(any(), any())).thenAnswer((_) async =>
    (md5: 'test_md5', packedSize: 500, uncompressedSize: 700));

    revisionService = RevisionService(
      config: mockConfig,
      packer: mockPacker,
      dbService: mockDb,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('getInitialState', () {
    test('Correctly reads base minimum versions from the configuration', () {
      final state = revisionService.getInitialState;

      expect(state.elementCurrentVer, 30);
      expect(state.launcherCurrentVer, 10);
      expect(state.patcherCurrentVer, 20);
    });
  });

  group('createInitial', () {
    test('Creates the directory structure, cleans the database and initializes version files', () async {
      when(() => mockDb.isConnected).thenReturn(false);
      when(() => mockDb.execute(any(), any())).thenAnswer((_) async =>
      (affectedRows: 1, rows: <Map<String, dynamic>>[]));

      final oldTypeDir = Directory(path.join(tempDir.path, 'patch', 'cpw', 'element'))..createSync(recursive: true);
      final oldFile = File(path.join(oldTypeDir.path, 'old_version.inc'))..createSync();

      final state = await revisionService.createInitial();

      expect(state.elementCurrentVer, equals(30));
      expect(state.launcherCurrentVer, equals(10));
      expect(state.patcherCurrentVer, equals(20));

      expect(oldFile.existsSync(), isFalse, reason: 'Old CPW files need to be deeply cleaned');

      for (final type in ['element', 'launcher', 'patcher']) {
        final inputDir = Directory(path.join(tempDir.path, 'patch', 'new', type));
        final outputDir = Directory(path.join(tempDir.path, 'patch', 'cpw', type, type));
        final versionFile = File(path.join(tempDir.path, 'patch', 'cpw', type, 'version'));

        expect(inputDir.existsSync(), true, reason: 'Input folder for $type must be created');
        expect(outputDir.existsSync(), true, reason: 'Output folder for $type must be created');
        expect(versionFile.existsSync(), true, reason: 'The version file for $type must exist');
        expect(versionFile.readAsStringSync().trim(), '${state.getCurrent(type)}');
      }

      final pidFile = File(path.join(tempDir.path, 'patch', 'cpw', 'info', 'pid'));
      expect(pidFile.existsSync(), isTrue);
      expect(pidFile.readAsStringSync(), equals('101'));

      verify(() => mockDb.initialize()).called(1);
      verify(() => mockDb.execute('TRUNCATE TABLE `files`')).called(1);
      verify(() => mockDb.dispose()).called(1);
    });
  });

  group('syncVersionFilesToDb', () {
    test('Successfully parses the state from DB if it is available', () async {
      when(() => mockDb.isConnected).thenReturn(true);
      final dbResult = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': '42'},
        {'type': 'launcher', 'max_rev': 12},
      ]);
      when(() => mockDb.execute(any(), any())).thenAnswer((_) async => dbResult);

      final state = await revisionService.syncVersionFilesToDb();

      expect(state.elementCurrentVer, equals(42));
      expect(state.launcherCurrentVer, equals(12));
      expect(state.patcherCurrentVer, equals(1));
    });

    test('When a DatabaseQueryException error occurs, it crashes while reading versions from files on disk.',
            () async {
      when(() => mockDb.isConnected).thenReturn(true);
      when(() => mockDb.execute(any(), any())).thenThrow(const DatabaseQueryException('SQL Error'));

      File(path.join(tempDir.path, 'patch', 'cpw', 'element', 'version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('55\n');
      File(path.join(tempDir.path, 'patch', 'cpw', 'launcher', 'version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('15\n');

      final state = await revisionService.syncVersionFilesToDb();

      expect(state.elementCurrentVer, equals(55));
      expect(state.launcherCurrentVer, equals(15));
      expect(state.patcherCurrentVer, equals(1)); // there was no file
    });
  });

  group('createNext and _packFiles', () {
    test('Increments versions, packages files, and stores metadata in the database.', () async {
      when(() => mockDb.isConnected).thenReturn(true);

      final initialDbState = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': 5},
        {'type': 'launcher', 'max_rev': 5},
        {'type': 'patcher', 'max_rev': 5}
      ]);

      when(() => mockDb.execute(any(), any())).thenAnswer((invocation) async {
        final query = invocation.positionalArguments[0] as String;
        if (query.contains('SELECT type')) return initialDbState;
        return (affectedRows: 1, rows: <Map<String, dynamic>>[]);
      });

      final inputDir = Directory(path.join(tempDir.path, 'patch', 'new', 'element'))..createSync(recursive: true);
      final validFile = File(path.join(inputDir.path, 'config.ini'))..writeAsStringSync('data');
      final subDir = Directory(path.join(inputDir.path, 'models'))..createSync();
      final validSubFile = File(path.join(subDir.path, 'player.ecd'))..writeAsStringSync('mesh');
      File(path.join(inputDir.path, '.gitkeep')).writeAsStringSync('ignore');
      File(path.join(inputDir.path, '.DS_Store')).writeAsStringSync('ignore');

      final nextState = await revisionService.createNext();
      expect(nextState.elementCurrentVer, equals(6));

      verify(() => mockPacker.pack(any(that: predicate<File>((f) => f.path.contains('config.ini'))), any())).called(1);
      verify(() => mockPacker.pack(any(that: predicate<File>((f) => f.path.contains('player.ecd'))), any())).called(1);
      verifyNever(() => mockPacker.pack(any(that: predicate<File>((f) => f.path.contains('.gitkeep'))), any()));
      verifyNever(() => mockPacker.pack(any(that: predicate<File>((f) => f.path.contains('.DS_Store'))), any()));

      verify(() => mockDb.execute(any(that: contains('INSERT INTO files')), any())).called(2);

      expect(validFile.existsSync(), isFalse);
      expect(validSubFile.existsSync(), isFalse);
      expect(subDir.existsSync(), isFalse, reason: 'Empty subfolders within the structure should also be deleted.');
      expect(inputDir.existsSync(), isTrue);

      final versionFile = File(mockConfig.resolvePath('patch/cpw/element/version'));
      expect(versionFile.readAsStringSync().trim(), '6');
    });

    test('In force: true mode, does not increase the version and clears old revision records in the database.',
            () async {
      when(() => mockDb.isConnected).thenReturn(true);
      final dbResult = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': 10},
        {'type': 'launcher', 'max_rev': 10},
        {'type': 'patcher', 'max_rev': 10}
      ]);

      when(() => mockDb.execute(any(), any())).thenAnswer((_) async => dbResult);

      for (final type in ['element', 'launcher', 'patcher']) {
        Directory(path.join(tempDir.path, 'patch', 'new', type))
            .createSync(recursive: true);
      }

      final state = await revisionService.createNext(force: true);

      expect(state.elementCurrentVer, equals(10));

      verify(() => mockDb.execute(any(that: contains('DELETE FROM files WHERE type = :type')), any())).called(3);
    });
  });
}
