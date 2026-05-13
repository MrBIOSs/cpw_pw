import 'dart:io';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/config/config.dart';

class MockDatabase extends Mock implements IDatabase {}

void main() {
  late DbService dbService;
  late MockDatabase mockDb;
  late PatcherConfig mockConfig;
  late Directory tempDir;

  setUp(() async {
    mockDb = MockDatabase();
    tempDir = await Directory.systemTemp.createTemp('db_service_test_');
    mockConfig = PatcherConfig(
      baseDir: tempDir.path,
      dbHost: 'localhost',
      dbUser: 'user',
      dbPassword: 'password',
      dbName: 'test_db',
      patchPath: 'files',
      patchNewDir: 'new',
      patchCpwDir: 'CPW',
      minLauncherVer: 1,
      minPatcherVer: 1,
      minElementVer: 1,
      removeFolders: true,
      removeFiles: true,
      addSize: true,
    );
    dbService = DbService(config: mockConfig, adapter: mockDb);

    when(() => mockDb.type).thenReturn(DbType.mysql);
    when(() => mockDb.connect()).thenAnswer((_) async => {});
    when(() => mockDb.close()).thenAnswer((_) async => {});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('DbService.initialize', () {
    test('should call connect on adapter', () async {
      await dbService.initialize();
      verify(() => mockDb.connect()).called(1);
    });
  });

  group('DbService.checkRequiredTables', () {
    test('should return empty list when all tables exist', () async {
      when(() => mockDb.execute(any(), any())).thenAnswer((_) async =>
      (affectedRows: 0, rows: [{'1': '1'}])
      );

      final missing = await dbService.checkRequiredTables(['files']);

      expect(missing, isEmpty);
      verify(() => mockDb.execute(any(), any())).called(1);
    });

    test('should return missing tables when they are not in schema', () async {
      when(() => mockDb.execute(any(), any())).thenAnswer((_) async =>
      (affectedRows: 0, rows: <Map<String, dynamic>>[])
      );

      final missing = await dbService.checkRequiredTables(['ghost_table']);

      expect(missing, contains('ghost_table'));
    });

    test('should use fallback check if information_schema query fails', () async {
      when(() => mockDb.execute(any(that: contains('information_schema')), any()))
          .thenThrow(Exception('Access denied'));

      when(() => mockDb.execute(any(that: contains('LIMIT 0')), any()))
          .thenAnswer((_) async => (affectedRows: 0, rows: <Map<String, dynamic>>[]));

      final missing = await dbService.checkRequiredTables(['fallback_test']);

      expect(missing, isEmpty);
    });
  });

  group('DbService.runInstallScript', () {
    test('should throw FileSystemException if script file missing', () async {
      expect(
            () => dbService.runInstallScript(customPath: tempDir.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('should read file and call executeScript', () async {
      final scriptFile = File(p.join(tempDir.path, 'install_mysql.sql'));
      await scriptFile.writeAsString('CREATE TABLE test;');

      when(() => mockDb.executeScript(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => (totalQueries: 1, successfulQueries: 1, results: <QueryResult>[]));

      await dbService.runInstallScript(customPath: scriptFile.path);

      verify(() => mockDb.executeScript('CREATE TABLE test;', onProgress: any(named: 'onProgress'))).called(1);
    });
  });

  group('DbService.dispose', () {
    test('should close connection if it was connected', () async {
      when(() => mockDb.isConnected).thenReturn(true);
      await dbService.dispose();
      verify(() => mockDb.close()).called(1);
    });

    test('should not close if already disconnected', () async {
      when(() => mockDb.isConnected).thenReturn(false);
      await dbService.dispose();
      verifyNever(() => mockDb.close());
    });
  });
}
