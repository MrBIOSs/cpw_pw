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
      dbPort: 3306,
      dbUser: 'user',
      dbPassword: 'password',
      dbName: 'test_db',
      patchPath: 'files',
      patchNewDir: 'new',
      patchCpwDir: 'CPW',
      minLauncherVer: 1,
      minPatcherVer: 1,
      minElementVer: 1,
      removeFiles: true,
      addSize: true,
    );
    dbService = DbService(config: mockConfig, adapter: mockDb);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DbService', () {
    test('Returns metadata correctly (type, isConnected)', () {
      when(() => mockDb.type).thenReturn(DbType.mysql);
      when(() => mockDb.isConnected).thenReturn(true);

      expect(dbService.type, DbType.mysql);
      expect(dbService.isConnected, isTrue);
    });
  });

  group('DbService.initialize', () {
    test('should call connect on adapter', () async {
      when(() => mockDb.connect()).thenAnswer((_) async {});
      await dbService.initialize();
      verify(() => mockDb.connect()).called(1);
    });
  });

  group('DbService.execute', () {
    test('execute translates the request and parameters to the adapter', () async {
      final expectedResult = (affectedRows: 1, rows: <Map<String, dynamic>> []);
      when(() => mockDb.execute('SELECT * FROM users', {'id': 1}))
          .thenAnswer((_) async => expectedResult);

      final result = await dbService.execute('SELECT * FROM users', {'id': 1});
      expect(result, equals(expectedResult));
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

    test('Adds a table to missing if both the main query and the fallback check fail.', () async {
      when(() => mockDb.execute(any(that: contains('information_schema')), any()))
          .thenThrow(Exception('Access denied'));
      when(() => mockDb.execute(any(that: contains('LIMIT 0')), any()))
          .thenThrow(const DatabaseQueryException('Table does not exist'));

      final missing = await dbService.checkRequiredTables(['files']);
      expect(missing, contains('files'));
    });
  });

  group('DbService.runTransaction ', () {
    test('runTransaction correctly proxies the call', () async {
      when(() => mockDb.runTransaction<String>(any()))
          .thenAnswer((invocation) async => 'transaction_success');

      final result = await dbService.runTransaction((tx) async => 'success');
      expect(result, equals('transaction_success'));
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
      when(() => mockDb.type).thenReturn(DbType.mysql);

      final scriptDir = Directory(p.join(tempDir.path, 'config'))..createSync();
      File(p.join(scriptDir.path, 'install_mysql.sql'))
        .writeAsStringSync('CREATE TABLE files; INSERT INTO files;');

      when(() => mockDb.executeScript(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => (totalQueries: 2, successfulQueries: 2, results: <QueryResult>[]));

      final result = await dbService.runInstallScript();

      expect(result.successfulQueries, equals(2));
      expect(result.totalQueries, equals(2));
      verify(() => mockDb.executeScript('CREATE TABLE files; INSERT INTO files;', onProgress: any(named: 'onProgress')))
          .called(1);
    });
  });

  group('DbService.dispose', () {
    test('should close connection if it was connected', () async {
      when(() => mockDb.isConnected).thenReturn(true);
      when(() => mockDb.close()).thenAnswer((_) async {});
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
