import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cpw_pw/core/crypto/crypto.dart';
import 'package:cpw_pw/features/security/security.dart';

class MockKeyStorage extends Mock implements IKeyStorage {}

void main() {
  late BinaryPatcherService patcherService;
  late MockKeyStorage mockStorage;
  late Directory tempDir;
  late RsaKeyPair testKeyPair;

  setUpAll(() {
    testKeyPair = (
    p: BigInt.zero,
    q: BigInt.zero,
    modulus: BigInt.parse(
        '1222851412030062489240409749102485501064846430310248501248501648493'
            '1024850124850164849310248501248501648493102485012485016484931024850'
            '1248501648493102485012485016484931024850124850164849310248501248501'
            '6484931024850124850164849310248501248501648493102485012485016484931'
            '02485012485016484931024850124850164849313'
    ),
    publicExponent: BigInt.from(65537),
    privateExponent: BigInt.zero,
    publicKeyPem: '',
    privateKeyPem: '',
    );
  });

  setUp(() {
    mockStorage = MockKeyStorage();
    patcherService = BinaryPatcherService(keyStorage: mockStorage);
    tempDir = Directory.systemTemp.createTempSync('patcher_test_');

    when(() => mockStorage.load()).thenAnswer((_) async => testKeyPair);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('BinaryPatcherService - patchExecutable', () {
    test('Throws FileSystemException if the executable does not exist.', () async {
      expect(
            () => patcherService.patchExecutable(executablePath: '${tempDir.path}/non_existent.exe'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Throws a FileSystemException if the passed path is a directory.', () async {
      expect(
            () => patcherService.patchExecutable(executablePath: tempDir.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Throws a StateError if the placeholder marker is not found in the file.', () async {
      final fakeExe = File('${tempDir.path}/launcher.exe')
        ..writeAsStringSync('SAMP_EXECUTABLE_DATA_WITHOUT_MARKER_ANYWHERE');

      expect(
            () => patcherService.patchExecutable(executablePath: fakeExe.path),
        throwsA(isA<StateError>().having(
              (e) => e.message,
          'message',
          contains('not found in executable'),
        )),
      );
    });

    test('Throws a StateError if there is not enough space between BEGIN and END markers.',
            () async {
      const startMarker = '-----BEGIN PUBLIC KEY-----';
      const endMarker = '-----END PUBLIC KEY-----';
      final fakeExe = File('${tempDir.path}/launcher.exe')
        ..writeAsStringSync('$startMarker\n${'0' * 50}\n$endMarker');

      expect(
            () => patcherService.patchExecutable(executablePath: fakeExe.path),
        throwsA(isA<StateError>().having(
              (e) => e.message,
          'message',
          contains('Not enough space between PEM markers'),
        )),
      );
    });

    test('In isHelp: true mode, returns the correct PatchResult, but does not modify the file.',
            () async {
      const startMarker = '-----BEGIN PUBLIC KEY-----';
      const endMarker = '-----END PUBLIC KEY-----';
      final fileContent = '$startMarker\n${'0' * 250}\n$endMarker';
      final fakeExe = File('${tempDir.path}/launcher.exe')..writeAsStringSync(fileContent);
      final result = await patcherService.patchExecutable(
        executablePath: fakeExe.path,
        isHelp: true,
      );

      expect(result.patched, isFalse);
      expect(result.keySize, equals(219));
      expect(result.originalSize, equals(startMarker.length));
      // Marker position (0) + marker length (26) + 1 byte '\n' = 27
      expect(result.markerOffset, equals(27));
      expect(fakeExe.readAsStringSync(), equals(fileContent));
    });

    test('Successfully performs key injection and successfully passes verification verify: true',
            () async {
      const startMarker = '-----BEGIN PUBLIC KEY-----';
      const endMarker = '-----END PUBLIC KEY-----';
      const zeroCount  = 250;

      final fileContent = '$startMarker\n${'0' * zeroCount }\n$endMarker';
      final fakeExe = File('${tempDir.path}/launcher.exe')..writeAsStringSync(fileContent);

      final result = await patcherService.patchExecutable(
        executablePath: fakeExe.path,
      );

      expect(result.patched, isTrue);
      expect(result.markerOffset, equals(startMarker.length + 1));
      expect(result.keySize, equals(219));

      final patchedBytes = fakeExe.readAsBytesSync();
      final patchedString = utf8.decode(patchedBytes);

      expect(patchedString.startsWith(startMarker), isTrue);
      expect(patchedString.endsWith(endMarker), isTrue);

      final endOffset = patchedString.indexOf(endMarker);
      final actualAvailableSpace = endOffset - result.markerOffset;

      final injectedBytes = patchedBytes.sublist(result.markerOffset, result.markerOffset + actualAvailableSpace);
      final injectedString = utf8.decode(injectedBytes);
      final keyString = injectedString.substring(0, 219);

      expect(keyString.contains('\n'), isTrue);

      final lines = injectedString.split('\n');
      expect(lines.length, equals(4));
      expect(lines[0].length, equals(64));
      expect(lines[1].length, equals(64));
      expect(lines[2].length, equals(64));
      expect(lines[3].trim().length, equals(24));

      final paddingString = injectedString.substring(219);
      expect(paddingString.length, equals(actualAvailableSpace - 219));
      expect(paddingString.trim(), isEmpty);
      expect(paddingString.codeUnits.every((code) => code == 32), isTrue);
    });
  });
}