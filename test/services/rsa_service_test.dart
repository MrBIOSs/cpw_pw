import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/core/crypto/crypto.dart';

class MockKeyStorage extends Mock implements IKeyStorage {}

void main() {
  late RsaService rsaService;
  late MockKeyStorage mockStorage;
  late Directory tempDir;
  late RsaKeyPair stubKeyPair;

  setUpAll(() {
    registerFallbackValue((
    p: BigInt.zero,
    q: BigInt.zero,
    modulus: BigInt.zero,
    publicExponent: BigInt.zero,
    privateExponent: BigInt.zero,
    publicKeyPem: '',
    privateKeyPem: '',
    ));
    stubKeyPair = (
    p: BigInt.parse('12864928143757622357883221546280546407815199202312665205961303779628617821440857110175791155676211770159595489876776627416236476124102700390846681969152371'),
    q: BigInt.parse('9520622618618094718921566864683284302663630449687791808582016847161960733921111101141482200664431919998956553083587530844658770995312345447046385328270877'),
    modulus: BigInt.parse('122482125872355319075327512201688285470199702628389791731629695931090715196474263953383232542789942242732372090629577862233527099051337352430152502648962810429827018986209724417878998360393484020103543704809030738594338262183214059421612401188969697017063177876885654474192832744784601245727032282570774799367'),
    publicExponent: BigInt.from(65537),
    privateExponent: BigInt.parse('63021190572374288028733677753835706155921146410911884385649098623560889377608200783863099998099083607232224838917252774652131884387600086383221272591447185187619812459563644508613877620267837810478003298326965502247964120023508795593727786604794207703534058389200306515166635600321244866447969177845289845433'),
    publicKeyPem: '-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCua5szCUOK0YgqZqvTPgyY7io2\nCTF8U9rP71xoajs5uAasYAEspq6gbi8p63WW9Lak9tNled4dCGWyW321GGpZsIxw\nCQiTyD9TkeOZahpZlnJOH5hlmclGuJYpmfahc3gSjr6XJVMqgbhIfU5fUKWfUo2F\nOSqY+zCSJQoRoJPkBwIDAQAB\n-----END PUBLIC KEY-----',
    privateKeyPem: '',
    );
  });

  setUp(() {
    mockStorage = MockKeyStorage();
    rsaService = RsaService(storage: mockStorage);
    tempDir = Directory.systemTemp.createTempSync('rsa_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('RsaService - Unit Tests', () {
    test('loadKeys throws KeyNotFoundException when storage is empty', () async {
      when(() => mockStorage.hasKeys()).thenReturn(false);

      expect(
            () => rsaService.loadKeys(),
        throwsA(isA<KeyNotFoundException>()),
      );

      verify(() => mockStorage.hasKeys()).called(1);
    });

    test('hasKeys calls storage.hasKeys', () {
      when(() => mockStorage.hasKeys()).thenReturn(true);
      expect(rsaService.hasKeys(), isTrue);

      when(() => mockStorage.hasKeys()).thenReturn(false);
      expect(rsaService.hasKeys(), isFalse);
    });

    test('deleteKeys calls storage.delete', () async {
      when(() => mockStorage.delete()).thenAnswer((_) async => {});

      await rsaService.deleteKeys();

      verify(() => mockStorage.delete()).called(1);
    });

    test('loadKeys successfully reads keys if they are present', () async {
      when(() => mockStorage.hasKeys()).thenReturn(true);
      when(() => mockStorage.load()).thenAnswer((_) async => stubKeyPair);

      final result = await rsaService.loadKeys();
      expect(result.modulus, equals(stubKeyPair.modulus));
    });

    test('formatPublicKeyForCopy generates correct string format', () {
      final dump = RsaService.formatPublicKeyForCopy(stubKeyPair);

      expect(dump, contains('# RSA Public Key (copy-paste ready)'));
      expect(dump, contains('Exponent: 65537'));
      expect(dump, contains(stubKeyPair.publicKeyPem));
    });

    test('generateAndSave creates keys and persists them', () async {
      when(() => mockStorage.save(any())).thenAnswer((_) async => {});

      final result = await rsaService.generateAndSave(keySize: 512); // Small size for speed

      expect(result.p, isNotNull);
      expect(result.q, isNotNull);
      expect(result.modulus, isNotNull);
      expect(result.publicExponent, equals(BigInt.from(65537)));
      expect(result.publicKeyPem, startsWith('-----BEGIN PUBLIC KEY-----'));
      expect(result.privateKeyPem, startsWith('-----BEGIN RSA PRIVATE KEY-----'));

      verify(() => mockStorage.save(any())).called(1);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('signFile throws FileSystemException when attempting to sign a missing file', () async {
      when(() => mockStorage.hasKeys()).thenReturn(true);
      when(() => mockStorage.load()).thenAnswer((_) async => stubKeyPair);

      expect(
            () => rsaService.signFile(path.join(tempDir.path, 'ghost_manifest.md5')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('signFile successfully signs file and appends signature block', () async {
      when(() => mockStorage.hasKeys()).thenReturn(true);
      when(() => mockStorage.load()).thenAnswer((_) async => stubKeyPair);

      final testFile = File(path.join(tempDir.path, 'files.md5'))
        ..writeAsStringSync('# 1\n1af9388f0b7f36a80398fd0f95d646be dGVzdC5kYXQ\n');

      await rsaService.signFile(testFile.path);

      final fileContent = testFile.readAsStringSync();

      expect(fileContent, startsWith('# 1'));
      expect(fileContent, contains('-----BEGIN ELEMENT SIGNATURE-----'));

      final lines = fileContent.split('\n');
      final lastContentLine = lines[lines.length - 2];
      expect(lastContentLine, endsWith('='));

      final signatureBlockStart = lines.indexOf('-----BEGIN ELEMENT SIGNATURE-----');
      expect(signatureBlockStart, isNot(-1));

      final firstSignatureLine = lines[signatureBlockStart + 1];
      expect(firstSignatureLine.length, equals(64));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('signFile uses internal key caching when re-invoking a signature', () async {
      when(() => mockStorage.hasKeys()).thenReturn(true);
      when(() => mockStorage.load()).thenAnswer((_) async => stubKeyPair);

      final file1 = File(path.join(tempDir.path, 'manifest1.md5'))..writeAsStringSync('data1');
      final file2 = File(path.join(tempDir.path, 'manifest2.md5'))..writeAsStringSync('data2');

      await rsaService.signFile(file1.path);
      await rsaService.signFile(file2.path);

      verify(() => mockStorage.load()).called(1);
    });
  });
}