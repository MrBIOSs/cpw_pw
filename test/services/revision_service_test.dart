import 'dart:io';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/features/revisions/revisions.dart';
import 'package:cpw_pw/config/config.dart';

class MockPackerService extends Mock implements PackerService {}
class MockDbService extends Mock implements DbService {}

void main() {
  late RevisionService revisionService;
  late PatcherConfig realConfig;
  late MockPackerService mockPacker;
  late MockDbService mockDb;
  late Directory tempDir;

  setUp(() {
    mockPacker = MockPackerService();
    mockDb = MockDbService();
    tempDir = Directory.systemTemp.createTempSync('revision_test_');
    realConfig = PatcherConfig(
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
      removeFolders: false,
      removeFiles: false,
      addSize: true,
    );
    registerFallbackValue(File(''));

    when(() => mockDb.initialize()).thenAnswer((_) async {});
    when(() => mockDb.dispose()).thenAnswer((_) async {});

    revisionService = RevisionService(
      config: realConfig,
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
    test('Creates the directory structure and initializes version files', () async {
      final state = await revisionService.createInitial();

      expect(state.elementCurrentVer, 30);

      for (final type in ['element', 'launcher', 'patcher']) {
        final inputDir = Directory(realConfig.resolvePath('patch/new/$type'));
        final outputDir = Directory(realConfig.resolvePath('patch/cpw/$type/$type'));
        final versionFile = File(realConfig.resolvePath('patch/cpw/$type/version'));

        expect(inputDir.existsSync(), true, reason: 'Input folder for $type must be created');
        expect(outputDir.existsSync(), true, reason: 'Output folder for $type must be created');
        expect(versionFile.existsSync(), true, reason: 'The version file for $type must exist');
        expect(versionFile.readAsStringSync().trim(), '${state.getCurrent(type)}');
      }
    });
  });

  group('getCurrentState', () {
    test('Falls back to files and returns 1 if DB is not connected and files do not exist', () async {
      when(() => mockDb.isConnected).thenReturn(false);

      final state = await revisionService.getCurrentState();

      expect(state.elementCurrentVer, 1);
      expect(state.launcherCurrentVer, 1);
      expect(state.patcherCurrentVer, 1);
    });

    test('Falls back to files and parses them if DB is not connected', () async {
      when(() => mockDb.isConnected).thenReturn(false);

      File(realConfig.resolvePath('patch/cpw/element/version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('45\n');
      File(realConfig.resolvePath('patch/cpw/launcher/version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('12\n');

      final state = await revisionService.getCurrentState();

      expect(state.elementCurrentVer, 45);
      expect(state.launcherCurrentVer, 12);
      expect(state.patcherCurrentVer, 1);
    });

    test('Successfully reads state from DB when connected', () async {
      when(() => mockDb.isConnected).thenReturn(true);

      final QueryResult dbResult = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': 7},
        {'type': 'launcher', 'max_rev': '15'},
        {'type': 'patcher', 'max_rev': 3}
      ],
      );

      when(() => mockDb.execute(any(), any())).thenAnswer((_) async => dbResult);

      final state = await revisionService.getCurrentState();

      expect(state.elementCurrentVer, 7);
      expect(state.launcherCurrentVer, 15);
      expect(state.patcherCurrentVer, 3);
    });

    test('Falls back to files if DB throws DatabaseQueryException', () async {
      when(() => mockDb.isConnected).thenReturn(true);
      when(() => mockDb.execute(any(), any())).thenThrow(DatabaseQueryException('DB Error'));

      File(realConfig.resolvePath('patch/cpw/element/version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('99\n');

      final state = await revisionService.getCurrentState();

      expect(state.elementCurrentVer, 99);
      expect(state.launcherCurrentVer, 1);
    });
  });

  group('syncVersionFilesToDb', () {
    test('Auto-corrects and updates version files if they are out of sync with DB state', () async {
      when(() => mockDb.isConnected).thenReturn(true);

      final QueryResult dbResult = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': 20},
        {'type': 'launcher', 'max_rev': 20},
        {'type': 'patcher', 'max_rev': 20}
      ],
      );
      when(() => mockDb.execute(any(), any())).thenAnswer((_) async => dbResult);

      for (final type in ['element', 'launcher', 'patcher']) {
        final dir = Directory(realConfig.resolvePath('patch/cpw/$type'));
        dir.createSync(recursive: true);
      }

      final elementVersionFile = File(realConfig.resolvePath('patch/cpw/element/version'))
        ..createSync(recursive: true)
        ..writeAsStringSync('5\n');

      await revisionService.syncVersionFilesToDb();

      expect(elementVersionFile.readAsStringSync().trim(), '20');
    });
  });

  group('createNext and _packFiles', () {
    test('Increments versions, packages files, and stores metadata in the database.', () async {
      when(() => mockDb.isConnected).thenReturn(true);

      final QueryResult initialDbState = (
      affectedRows: 0,
      rows: [
        {'type': 'element', 'max_rev': 5},
        {'type': 'launcher', 'max_rev': 5},
        {'type': 'patcher', 'max_rev': 5}
      ],
      );

      when(() => mockDb.execute(any(), any())).thenAnswer((invocation) async {
        final query = invocation.positionalArguments[0] as String;
        if (query.contains('SELECT type')) return initialDbState;
        return (affectedRows: 1, rows: <Map<String, dynamic>>[]);
      });

      for (final type in ['element', 'launcher', 'patcher']) {
        final outputDir = Directory(realConfig.resolvePath('patch/cpw/$type/$type'));
        outputDir.createSync(recursive: true);
      }

      final elementInputDir = realConfig.resolvePath('patch/new/element');
      final subFolder = Directory('$elementInputDir/data')..createSync(recursive: true);

      File('${subFolder.path}/config.ini').writeAsStringSync('test data');
      File('$elementInputDir/.DS_Store').createSync();

      final PackResult mockPackResult = (uncompressedSize: 9, packedSize: 5, md5: 'abc123md5');
      when(() => mockPacker.pack(any(), any())).thenAnswer((_) async => mockPackResult);

      final nextState = await revisionService.createNext();

      expect(nextState.elementCurrentVer, 6);
      expect(nextState.launcherCurrentVer, 6);
      expect(nextState.patcherCurrentVer, 6);

      verify(() => mockPacker.pack(
        any(that: predicate<File>((f) => f.path.endsWith('config.ini'))),
        any(),
      )).called(1);

      verifyNever(() => mockPacker.pack(
        any(that: predicate<File>((f) => f.path.contains('.DS_Store'))),
        any(),
      ));

      verify(() => mockDb.execute(
          any(that: contains('INSERT INTO files')),
          any(that: isA<Map<String, dynamic>>()
              .having((m) => m['md5'], 'md5', 'abc123md5')
              .having((m) => m['folder'], 'folder', 'data')
              .having((m) => m['file'], 'file', 'config.ini')
              .having((m) => m['added'], 'added', 7)), // 6 + 1 = 7
      )).called(1);

      final versionFile = File(realConfig.resolvePath('patch/cpw/element/version'));
      expect(versionFile.readAsStringSync().trim(), '6');
    });
  });
}
