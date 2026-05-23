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
  /// [marker] — unique placeholder string in the source code.
  /// [verify] — read the file after writing and verify its integrity.
  Future<PatchResult> patchExecutable({
    required String executablePath,
    String marker = '-----BEGIN PUBLIC KEY-----',
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
    final markerBytes = utf8.encode(marker);
    final markerOffset = _findBytePattern(originalBytes, markerBytes);

    if (markerOffset == -1) {
      throw StateError(
          'Marker "$marker" not found in executable. '
              'Ensure the binary contains the exact placeholder string in its source code.'
      );
    }

    final injectionOffset = markerOffset + markerBytes.length + 1;
    if (injectionOffset + _fixedKeySize > originalBytes.length) {
      throw StateError(
          'Not enough space in executable to inject the key after the marker.'
      );
    }

    final result = (
    markerOffset: injectionOffset,
    originalSize: markerBytes.length,
    keySize: keyData.length,
    patched: !isHelp,
    );

    if (isHelp) {
      log.info('Help mod: would patch at offset $injectionOffset');
      return result;
    }

    final patchedBytes = Uint8List.fromList(originalBytes);
    final paddedKey = _padToFixedFormat(keyData);

    patchedBytes.setRange(
        injectionOffset,
        injectionOffset + _fixedKeySize,
        paddedKey
    );

    await file.writeAsBytes(patchedBytes);
    log.info('Patched executable at offset $injectionOffset');

    if (verify) {
      final verifyBytes = await file.readAsBytes();
      final embedded = verifyBytes.sublist(injectionOffset, injectionOffset + _fixedKeySize);
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
    for (var i = 0; i <= data.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Uint8List _padToFixedFormat(Uint8List source) {
    if (source.length > _fixedKeySize) {
      throw StateError('Serialized key (${source.length} bytes) exceeds fixed format size ($_fixedKeySize).');
    }
    return Uint8List(_fixedKeySize)..setAll(0, source);
  }

  bool _arraysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}