import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

import 'package:cpw_pw/core/crypto/crypto.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';

/// Service for generating and managing RSA keys.
class RsaService {
  RsaService({
    required IKeyStorage storage,
    SecureRandom? random,
  })  : _storage = storage,
        _random = random ?? _createSecureRandom();

  final IKeyStorage _storage;
  final SecureRandom _random;

  static const _keySize = 1024;
  static final _publicExponent = BigInt.from(65537);

  /// Returns the public key in a format convenient for copying.
  static String formatPublicKeyForCopy(RsaKeyPair keys) {
    return '''
# RSA Public Key (copy-paste ready)
# Modulus (hex): ${keys.modulus.toRadixString(16)}
# Exponent: ${keys.publicExponent}

${keys.publicKeyPem}
''';
  }

  RsaKeyPair? _cachedKeys;

  /// [keySize] — key length in bits (default 1024).
  Future<RsaKeyPair> generateAndSave({int keySize = _keySize}) async {
    log.info('Generating RSA-$keySize key pair...');

    final keyPair = await _generateKeyPair(keySize: keySize);

    log.info('Saving keys to storage...');
    await _storage.save(keyPair);

    log.info('Keys generated and saved');
    return keyPair;
  }

  /// Loads existing keys from the repository.
  Future<RsaKeyPair> loadKeys() async {
    if (!_storage.hasKeys()) {
      throw const KeyNotFoundException('No keys found. Run "./cpw rsagen" first.');
    }
    return _storage.load();
  }

  /// Checks if there are any saved keys.
  bool hasKeys() => _storage.hasKeys();

  /// Deletes saved keys (for reset).
  Future<void> deleteKeys() => _storage.delete();

  static SecureRandom _createSecureRandom() {
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final random = math.Random.secure();

    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }

    secureRandom.seed(KeyParameter(seed));
    return secureRandom;
  }

  /// Signs a file with a private key and appends the signature to the end of the file.
  /// Signature format: "-----BEGIN ELEMENT SIGNATURE-----\n(base64-signature)"
  Future<void> signFile(String filePath) async {
    final keys =  await _getOrLoadKeys();
    final file = File(filePath);

    if (!file.existsSync()) {
      throw FileSystemException('File not found for signing', filePath);
    }
    final textContent = await file.readAsString();
    final normalizedText = textContent.replaceAll('\r\n', '\n').replaceAll('\r', '');
    final contentBytes = Uint8List.fromList(utf8.encode(normalizedText));

    final signature = _signWithMd5Rsa(data: contentBytes, key: keys);
    final signatureBase64 = base64Encode(signature);

    final sink = file.openWrite(mode: FileMode.append)
      ..write('-----BEGIN ELEMENT SIGNATURE-----\n');

    for (var i = 0; i < signatureBase64.length; i += 64) {
      final end = i + 64 > signatureBase64.length ? signatureBase64.length : i + 64;
      sink
        ..write(signatureBase64.substring(i, end))
        ..write('\n');
    }
    await sink.flush();
    await sink.close();

    log.fine('Signed: $filePath');
  }

  Future<RsaKeyPair> _getOrLoadKeys() async {
    if (_cachedKeys != null) return _cachedKeys!;

    _cachedKeys = await loadKeys();
    return _cachedKeys!;
  }

  Uint8List _signWithMd5Rsa({
    required Uint8List data,
    required RsaKeyPair key,
  }) {
    final privateKey = RSAPrivateKey(key.modulus, key.privateExponent, key.p, key.q);
    final md5 = MD5Digest();

    final signer = RSASigner(md5, '06082a864886f70d0205') // special OID prefix for MD5 in PKCS#1 v1.5
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final signature = signer.generateSignature(data);
    return signature.bytes;
  }

  Future<RsaKeyPair> _generateKeyPair({required int keySize}) async {
    final rsa = RSAKeyGenerator();
    final params = RSAKeyGeneratorParameters(_publicExponent, keySize, 12); // probability of primality (2^-12)

    rsa.init(ParametersWithRandom(params, _random));

    // Generation may take 1-5 seconds depending on the CPU
    final pair = await Isolate.run(rsa.generateKeyPair);
    final publicKey = pair.publicKey;
    final privateKey = pair.privateKey;

    return (
    p: privateKey.p!,
    q: privateKey.q!,
    modulus: publicKey.modulus!,
    publicExponent: publicKey.exponent!,
    privateExponent: privateKey.privateExponent!,
    publicKeyPem: _encodePublicKeyPem(publicKey),
    privateKeyPem: _encodePrivateKeyPem(privateKey),
    );
  }

  /// Encodes the public key in PEM (SubjectPublicKeyInfo, PKCS#8).
  String _encodePublicKeyPem(RSAPublicKey key) {
    final der = RsaUtils.encodeSubjectPublicKeyInfo(key);
    return RsaUtils.toPem('PUBLIC KEY', der);
  }

  /// Encodes the private key in PEM (RSAPrivateKey, PKCS#1).
  String _encodePrivateKeyPem(RSAPrivateKey key) {
    final der = RsaUtils.encodeRsaPrivateKey(key);
    return RsaUtils.toPem('RSA PRIVATE KEY', der);
  }
}