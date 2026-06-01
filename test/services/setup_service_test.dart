import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/features/setup/setup.dart';
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/core/crypto/crypto.dart';

class MockDbService extends Mock implements DbService {}
class MockRsaService extends Mock implements RsaService {}

void main() {
  late SetupService setupService;
  late MockDbService mockDb;
  late MockRsaService mockRsa;
  late PatcherConfig mockConfig;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('setup_test_');
    mockConfig = PatcherConfig(
      baseDir: tempDir.path,
      dbHost: 'localhost', dbPort: 3306, dbUser: 'u', dbPassword: 'p', dbName: 'n',
      patchPath: 'files', patchNewDir: 'new', patchCpwDir: 'cpw',
      minLauncherVer: 1, minPatcherVer: 1, minElementVer: 1,
      removeFiles: true, addSize: true,
    );
    mockDb = MockDbService();
    mockRsa = MockRsaService();

    Directory(path.join(tempDir.path, 'config')).createSync(recursive: true);

    when(() => mockDb.initialize()).thenAnswer((_) async {});
    when(() => mockDb.dispose()).thenAnswer((_) async {});

    setupService = SetupService(
      dbService: mockDb,
      rsaService: mockRsa,
      config: mockConfig,
    );

    File('${tempDir.path}/config/install.sql').writeAsStringSync('SELECT 1;');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SetupService - Successful Scenarios', () {
    test('Full installation (DB + Keys) when everything is clean', () async {
      when(() => mockDb.initialize()).thenAnswer((_) async => {});
      when(() => mockDb.checkRequiredTables(any())).thenAnswer((_) async => ['files']);
      when(() => mockDb.runInstallScript()).thenAnswer((_) async => (totalQueries: 1, successfulQueries: 1, results: <QueryResult>[]));
      when(() => mockDb.dispose()).thenAnswer((_) async => {});
      when(() => mockRsa.hasKeys()).thenReturn(false);
      when(() => mockRsa.generateAndSave()).thenAnswer((_) async => _mockKeyPair());

      final result = await setupService.initialize();

      expect(result.isCompleted, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.errors, isEmpty);

      expect(result.steps, contains('Environment validated'));
      expect(result.steps, contains('Database connected'));
      expect(result.steps, contains('Database initialized (1 tables)'));
      expect(result.steps, contains('RSA keys generated (1024-bit)'));

      verify(() => mockDb.initialize()).called(1);
      verify(() => mockDb.runInstallScript()).called(1);
      verify(() => mockRsa.generateAndSave()).called(1);
      verify(() => mockDb.dispose()).called(1);
    });

    test('Successful initialization if the database is already deployed and the keys are already generated',
            () async {
          when(() => mockDb.checkRequiredTables(['files'])).thenAnswer((_) async => <String>[]);
          when(() => mockRsa.hasKeys()).thenReturn(true);

          final result = await setupService.initialize();

          expect(result.isSuccess, isTrue);
          expect(result.steps, contains('Database schema already exists'));
          expect(result.steps, contains('RSA keys already exist'));

          verifyNever(() => mockDb.runInstallScript());
          verifyNever(() => mockRsa.generateAndSave());
        });

    test('Skipping steps using the skipDb and skipKeys flags', () async {
      when(() => mockRsa.hasKeys()).thenReturn(true);

      final result = await setupService.initialize(skipDb: true, skipKeys: true);

      expect(result.isSuccess, isTrue);
      expect(result.steps, anyElement(contains('Database setup skipped')));
      expect(result.steps, anyElement(contains('Key generation skipped')));

      verifyNever(() => mockDb.initialize());
      verifyNever(() => mockRsa.hasKeys());
      verifyNever(() => mockRsa.generateAndSave());
    });
  });

  group('SetupService - Error Handling', () {
    test('Terminates and returns an error if a DatabaseConnectionException is thrown on startup.', () async {
      when(() => mockDb.initialize()).thenThrow(const DatabaseConnectionException('Access denied for user root'));

      final result = await setupService.initialize();

      expect(result.isSuccess, isFalse);
      expect(result.errors.first, contains('Cannot connect to database: Access denied for user root'));

      verifyNever(() => mockRsa.hasKeys());
      verify(() => mockDb.dispose()).called(1);
    });

    test('Validation error (no write permission)', () async {
      await tempDir.delete(recursive: true);

      final result = await setupService.initialize();

      expect(result.isSuccess, isFalse);
      expect(result.errors, anyElement(contains('No write permission')));
    });

    test('Error connecting to the database interrupts the process', () async {
      when(() => mockDb.initialize()).thenThrow(const DatabaseConnectionException('Timeout'));
      when(() => mockDb.dispose()).thenAnswer((_) async => {});

      final result = await setupService.initialize();

      expect(result.isSuccess, isFalse);
      expect(result.errors, anyElement(contains('Cannot connect to database')));

      verifyNever(() => mockRsa.hasKeys());
    });

    test('Aborts and logs an error if a DatabaseScriptException occurs while rolling tables.', () async {
      when(() => mockDb.checkRequiredTables(['files'])).thenAnswer((_) async => ['files']);
      when(() => mockDb.runInstallScript())
          .thenThrow(const DatabaseScriptException('Syntax error near UNIQUE', failedAtLine: 42));

      final result = await setupService.initialize();

      expect(result.isSuccess, isFalse);
      expect(result.errors.first, contains('Database initialization failed: Syntax error near UNIQUE'));

      verifyNever(() => mockRsa.hasKeys());
      verify(() => mockDb.dispose()).called(1);
    });

    test('Returns a runtime error if the key generator throws a KeyGenerationException.', () async {
      when(() => mockDb.checkRequiredTables(['files'])).thenAnswer((_) async => <String>[]);
      when(() => mockRsa.hasKeys()).thenReturn(false);
      when(() => mockRsa.generateAndSave())
          .thenThrow(const KeyGenerationException('Fortuna PRNG seed entropy total failure'));

      final result = await setupService.initialize();

      expect(result.isSuccess, isFalse);
      expect(result.errors.first, contains('Failed to generate RSA keys: Fortuna PRNG seed entropy total failure'));
    });
  });

  group('SetupResult - Validation of the state of the result class', () {
    test('Throws a StateError when attempting to add a step to an already closed/completed SetupResult', () {
      final result = SetupResult.started()
        ..completed(success: true);

      expect(
            () => result.addStep('New step after completion'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Cannot add step to completed result'))),
      );
    });
  });
}

RsaKeyPair _mockKeyPair() => (
q: BigInt.one,
p: BigInt.one,
modulus: BigInt.one,
publicExponent: BigInt.one,
privateExponent: BigInt.one,
publicKeyPem: '',
privateKeyPem: '',
);
