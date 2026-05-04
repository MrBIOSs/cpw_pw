import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cpw_pw/features/security/security.dart';

class MockKeyStorage extends Mock implements IKeyStorage {}

void main() {
  late RsaService rsaService;
  late MockKeyStorage mockStorage;

  setUpAll(() {
    registerFallbackValue((
    modulus: BigInt.zero,
    publicExponent: BigInt.zero,
    privateExponent: BigInt.zero,
    publicKeyPem: '',
    privateKeyPem: '',
    ));
  });

  setUp(() {
    mockStorage = MockKeyStorage();
    rsaService = RsaService(storage: mockStorage);
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

      final result = rsaService.hasKeys();

      expect(result, isTrue);
      verify(() => mockStorage.hasKeys()).called(1);
    });

    test('deleteKeys calls storage.delete', () async {
      when(() => mockStorage.delete()).thenAnswer((_) async => {});

      await rsaService.deleteKeys();

      verify(() => mockStorage.delete()).called(1);
    });

    test('formatPublicKeyForCopy generates correct string format', () {
      final mockKeyPair = (
      modulus: BigInt.from(12345),
      publicExponent: BigInt.from(65537),
      privateExponent: BigInt.from(54321),
      publicKeyPem: 'BEGIN PUBLIC KEY...',
      privateKeyPem: 'BEGIN RSA PRIVATE KEY...',
      );

      final result = RsaService.formatPublicKeyForCopy(mockKeyPair);

      expect(result, contains('# Modulus (hex): 3039')); // 12345 in hex
      expect(result, contains('# Exponent: 65537'));
      expect(result, contains('BEGIN PUBLIC KEY...'));
    });

    test('generateAndSave creates keys and persists them', () async {
      when(() => mockStorage.save(any())).thenAnswer((_) async => {});

      final result = await rsaService.generateAndSave(keySize: 512); // Small size for speed

      expect(result.modulus, isNotNull);
      expect(result.publicKeyPem, startsWith('-----BEGIN PUBLIC KEY-----'));
      expect(result.privateKeyPem, startsWith('-----BEGIN RSA PRIVATE KEY-----'));

      verify(() => mockStorage.save(any())).called(1);
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}