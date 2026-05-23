import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pointycastle/asymmetric/api.dart';

import 'package:cpw_pw/core/crypto/crypto.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';

typedef PatchResult = ({
int markerOffset,
int originalSize,
int keySize,
bool patched,
});

/// A service for injecting public RSA keys into executable files.
final class BinaryPatcherService {
  BinaryPatcherService({required IKeyStorage keyStorage}) : _keyStorage = keyStorage;
  final IKeyStorage _keyStorage;

  // 216 Base64 + 3 '\n' = 219 bytes
  static const _fixedKeySize = 219;

  /// Patch the executable file, replacing the marker with a public RSA key.
  /// [executablePath] — path to the binary.
  /// [startMarker] — unique placeholder string in the source code.
  /// [verify] — read the file after writing and verify its integrity.
  Future<PatchResult> patchExecutable({
    required String executablePath,
    String startMarker = '-----BEGIN PUBLIC KEY-----',
    String endMarker = '-----END PUBLIC KEY-----',
    bool isHelp = false,
    bool verify = true,
  }) async {
    final file = File(executablePath);
    if (!file.existsSync()) {
      throw FileSystemException('Executable file not found', executablePath);
    }
    if (file.statSync().type == FileSystemEntityType.directory) {
      throw FileSystemException('Path is a directory, not an executable', executablePath);
    }

    final keys = await _keyStorage.load();
    log.fine('Loaded public key (modulus: ${keys.modulus.bitLength} bits)');

    final publicKey = _reconstructPublicKey(keys);
    final keyData = _serializeKeyForInjection(publicKey);
    log.fine('Serialized key size: ${keyData.length} bytes');

    final originalBytes = await file.readAsBytes();
    final startBytes = utf8.encode(startMarker);
    final endBytes = utf8.encode(endMarker);

    final startOffset = _findBytePattern(originalBytes, startBytes);
    final endOffset = _findBytePattern(originalBytes, endBytes);

    if (startOffset == -1 || endOffset == -1) {
      throw StateError(
          'PEM placeholders not found in executable. '
              'Ensure the binary contains intact BEGIN and END public key markers.'
      );
    }

    final injectionOffset = startOffset + startBytes.length + 1;
    final availableSpace = endOffset - injectionOffset;

    if (availableSpace < _fixedKeySize) {
      throw StateError(
          'Not enough space between PEM markers to inject the key. '
              'Available: $availableSpace bytes, Required: $_fixedKeySize bytes.'
      );
    }

    if (keyData.length > availableSpace) {
      throw StateError(
          'Serialized key (${keyData.length} bytes) exceeds available '
          'space inside the executable ($availableSpace bytes).'
      );
    }

    final result = (
    markerOffset: injectionOffset,
    originalSize: startBytes.length,
    keySize: keyData.length,
    patched: !isHelp,
    );

    if (isHelp) {
      log.info('Help mod: would patch at offset $injectionOffset');
      return result;
    }

    final patchedBytes = Uint8List.fromList(originalBytes);
    final paddedKey = Uint8List(availableSpace)
      ..fillRange(0, availableSpace, 32)
      ..setAll(0, keyData);

    patchedBytes.setRange(
        injectionOffset,
        injectionOffset + availableSpace,
        paddedKey
    );

    final tempFile = File('${file.path}.tmp');
    try {
      await tempFile.writeAsBytes(patchedBytes, flush: true);
      await tempFile.rename(file.path);
    } catch (e) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      rethrow;
    }
    log.info('Patched executable at offset $injectionOffset');

    if (verify) {
      final verifyBytes = await file.readAsBytes();
      final embedded = verifyBytes.sublist(injectionOffset, injectionOffset + availableSpace);
      if (!_arraysEqual(embedded, paddedKey)) {
        throw StateError('Verification failed: written data does not match expected.');
      }
      log.fine('Verification passed');
    }

    return result;
  }

  /// Reconstructs an RSAPublicKey from its components (for DER encoding).
  RSAPublicKey _reconstructPublicKey(RsaKeyPair keys) {
    return RSAPublicKey(keys.publicExponent, keys.modulus);
  }

  /// Base64(DER-encoded SubjectPublicKeyInfo), broken into 4 lines (64+64+64+24).
  Uint8List _serializeKeyForInjection(RSAPublicKey key) {
    final der = RsaUtils.encodeSubjectPublicKeyInfo(key);
    final base64 = base64Encode(der).replaceAll('=', '');

    if (base64.length < 216) {
      throw StateError('Base64 key too short: ${base64.length} < 216');
    }

    final lines = [
      base64.substring(0, 64),
      base64.substring(64, 128),
      base64.substring(128, 192),
      base64.substring(192, 216),
    ];
    return utf8.encode(lines.join('\n')); // 219 bytes
  }

  /// Searches for a sequence of bytes in data.
  int _findBytePattern(Uint8List data, Uint8List pattern) {
    if (pattern.isEmpty || data.length < pattern.length) return -1;
    if (pattern.length == 1) return data.indexOf(pattern[0]);

    var offset = data.indexOf(pattern[0]);

    while (offset != -1 && offset <= data.length - pattern.length) {
      var match = true;
      for (var j = 1; j < pattern.length; j++) {
        if (data[offset + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return offset;

      offset = data.indexOf(pattern[0], offset + 1);
    }
    return -1;
  }

  bool _arraysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}