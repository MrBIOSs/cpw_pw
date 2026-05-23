import 'dart:io';
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
  late PatcherConfig config;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('setup_test_');
    config = PatcherConfig(
      baseDir: tempDir.path,
      dbHost: 'localhost', dbPort: 3306, dbUser: 'u', dbPassword: 'p', dbName: 'n',
      patchPath: 'files', patchNewDir: 'new', patchCpwDir: 'cpw',
      minLauncherVer: 1, minPatcherVer: 1, minElementVer: 1,
      removeFolders: true, removeFiles: true, addSize: true,
    );
    mockDb = MockDbService();
    mockRsa = MockRsaService();
    setupService = SetupService(
      dbService: mockDb,
      rsaService: mockRsa,
      config: config,
    );

    Directory('${tempDir.path}/config').createSync();
    File('${tempDir.path}/config/install.sql').writeAsStringSync('SELECT 1;');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
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

      expect(result.isSuccess, isTrue);
      expect(result.steps, anyElement(contains('Database initialized')));
      expect(result.steps, anyElement(contains('RSA keys generated')));

      verify(() => mockDb.runInstallScript()).called(1);
      verify(() => mockRsa.generateAndSave()).called(1);
    });

    test('Skipping steps using the skipDb and skipKeys flags', () async {
      final result = await setupService.initialize(skipDb: true, skipKeys: true);

      expect(result.isSuccess, isTrue);
      expect(result.steps, anyElement(contains('Database setup skipped')));
      expect(result.steps, anyElement(contains('Key generation skipped')));

      verifyNever(() => mockDb.initialize());
      verifyNever(() => mockRsa.generateAndSave());
    });
  });

  group('SetupService - Error Handling', () {
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
