import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

    test('Throws a StateError if there is not enough space in the file after the marker for 219 bytes.',
            () async {
      final marker = '-----BEGIN PUBLIC KEY-----';
      final fakeExe = File('${tempDir.path}/launcher.exe')
        ..writeAsStringSync('$marker\n');

      expect(
            () => patcherService.patchExecutable(executablePath: fakeExe.path, marker: marker),
        throwsA(isA<StateError>().having(
              (e) => e.message,
          'message',
          contains('Not enough space in executable'),
        )),
      );
    });

    test('In isHelp: true mode, returns the correct PatchResult, but does not modify the file.',
            () async {
      final marker = '-----BEGIN PUBLIC KEY-----';
      final fileContent = '$marker\n${'0' * 250}';
      final fakeExe = File('${tempDir.path}/launcher.exe')..writeAsStringSync(fileContent);
      final result = await patcherService.patchExecutable(
        executablePath: fakeExe.path,
        marker: marker,
        isHelp: true,
      );

      expect(result.patched, isFalse);
      expect(result.keySize, equals(219));
      expect(result.originalSize, equals(marker.length));
      // Marker position (0) + marker length (26) + 1 byte '\n' = 27
      expect(result.markerOffset, equals(27));
      expect(fakeExe.readAsStringSync(), equals(fileContent));
    });

    test('Successfully performs key injection and successfully passes verification verify: true',
            () async {
      final marker = '-----BEGIN PUBLIC KEY-----';
      final markerBytes = utf8.encode(marker);
      final totalSize = markerBytes.length + 1 + 300;
      final dummyBytes = Uint8List(totalSize);

      dummyBytes.setRange(0, markerBytes.length, markerBytes);
      dummyBytes[markerBytes.length] = utf8.encode('\n').first;

      final fakeExe = File('${tempDir.path}/launcher.exe')..writeAsBytesSync(dummyBytes);
      final result = await patcherService.patchExecutable(
        executablePath: fakeExe.path,
        marker: marker,
      );

      expect(result.patched, isTrue);
      expect(result.markerOffset, equals(markerBytes.length + 1));
      expect(result.keySize, equals(219));

      final patchedBytes = fakeExe.readAsBytesSync();
      final readMarker = utf8.decode(patchedBytes.sublist(0, markerBytes.length));
      expect(readMarker, equals(marker));

      final injectedBytes = patchedBytes.sublist(result.markerOffset, result.markerOffset + 219);
      final injectedString = utf8.decode(injectedBytes);

      expect(injectedString.contains('\n'), isTrue);

      final lines = injectedString.split('\n');
      expect(lines.length, equals(4));
      expect(lines[0].length, equals(64));
      expect(lines[1].length, equals(64));
      expect(lines[2].length, equals(64));
      expect(lines[3].length, equals(24));
    });
  });
}