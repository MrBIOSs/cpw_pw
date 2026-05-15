import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

import '../../core/crypto/crypto.dart';
import '../../core/logger/logger_service.dart';
import 'key_storage_interface.dart';

/// Service for generating and managing RSA keys.
class RsaService {
  RsaService({
    required IKeyStorage storage,
    SecureRandom? random,
  })  : _storage = storage,
        _random = random ?? _createSecureRandom();

  final IKeyStorage _storage;
  final SecureRandom _random;

  static const _keySize = 2048;
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

  /// [keySize] — key length in bits (default 2048).
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
      throw KeyNotFoundException('No keys found. Run "./cpw rsagen" first.');
    }
    return await _storage.load();
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
  /// Signature format: "-----BEGIN ELEMENT SIGNATURE-----\n<base64-signature>"
  Future<void> signFile(String filePath) async {
    final keys = await loadKeys();
    final file = File(filePath);

    if (!file.existsSync()) {
      throw FileSystemException('File not found for signing', filePath);
    }
    final content = await file.readAsBytes();

    final signature = _signWithMd5Rsa(content, keys.privateExponent, keys.modulus);
    final signatureBase64 = base64Encode(signature).replaceAll('=', '');

    final sink = file.openWrite(mode: FileMode.append);
    sink.write('\n-----BEGIN ELEMENT SIGNATURE-----\n');

    for (var i = 0; i < signatureBase64.length; i += 64) {
      final end = i + 64 > signatureBase64.length ? signatureBase64.length : i + 64;
      sink.write(signatureBase64.substring(i, end));
      sink.write('\n');
    }
    await sink.flush();
    await sink.close();

    log.fine('Signed: $filePath');
  }

  Uint8List _signWithMd5Rsa(Uint8List data, BigInt privateExponent, BigInt modulus) {
    final privateKey = RSAPrivateKey(modulus, privateExponent, null, null);
    final signer = RSASigner(MD5Digest(), '0102082a864886f70d0205'); // DER prefix for MD5 OID

    signer.init(
      true,
      PrivateKeyParameter<RSAPrivateKey>(privateKey),
    );

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
    modulus: publicKey.modulus!,
    publicExponent: publicKey.exponent!,
    privateExponent: privateKey.privateExponent!,
    publicKeyPem: _encodePublicKeyPem(publicKey),
    privateKeyPem: _encodePrivateKeyPem(privateKey),
    );
  }

  /// Encodes the public key in PEM (SubjectPublicKeyInfo, PKCS#8).
  String _encodePublicKeyPem(RSAPublicKey key) {
    final der = _encodeSubjectPublicKeyInfo(key);
    return RsaUtils.toPem('PUBLIC KEY', der);
  }

  /// Encodes the private key in PEM (RSAPrivateKey, PKCS#1).
  String _encodePrivateKeyPem(RSAPrivateKey key) {
    final der = _encodeRsaPrivateKey(key);
    return RsaUtils.toPem('RSA PRIVATE KEY', der);
  }

  /// Encodes the public key in DER (SubjectPublicKeyInfo).
  /// Structure:
  /// SEQUENCE {
  ///   SEQUENCE { algorithm OID, NULL }
  ///   BIT STRING { SEQUENCE { modulus INTEGER, exponent INTEGER } }
  /// }
  Uint8List _encodeSubjectPublicKeyInfo(RSAPublicKey key) {
    final rsaSeq = ASN1Sequence();
    rsaSeq.add(ASN1Integer(key.modulus!));
    rsaSeq.add(ASN1Integer(key.exponent!));

    final algoSeq = ASN1Sequence();
    algoSeq.add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algoSeq.add(ASN1Null());

    final spki = ASN1Sequence();
    spki.add(algoSeq);
    spki.add(ASN1BitString(rsaSeq.encodedBytes));

    return spki.encodedBytes;
  }

  /// Encodes the private key in DER (RSAPrivateKey, PKCS#1).
  /// Structure:
  /// SEQUENCE {
  ///   version INTEGER,
  ///   modulus INTEGER, publicExponent INTEGER, privateExponent INTEGER,
  ///   prime1 INTEGER, prime2 INTEGER,
  ///   exponent1 INTEGER, exponent2 INTEGER, coefficient INTEGER
  /// }
  Uint8List _encodeRsaPrivateKey(RSAPrivateKey key) {
    final p = key.p!;
    final q = key.q!;
    final dP = key.privateExponent! % (p - BigInt.one); // d mod (p-1)
    final dQ = key.privateExponent! % (q - BigInt.one); // d mod (q-1)
    final qInv = RsaUtils.modInverse(q, p); // q^-1 mod p
    final seq = ASN1Sequence();

    seq.add(ASN1Integer(BigInt.zero));
    seq.add(ASN1Integer(key.modulus!));           // n
    seq.add(ASN1Integer(key.exponent!));          // e
    seq.add(ASN1Integer(key.privateExponent!));   // d
    seq.add(ASN1Integer(p));                      // p
    seq.add(ASN1Integer(q));                      // q
    seq.add(ASN1Integer(dP));                     // dP
    seq.add(ASN1Integer(dQ));                     // dQ
    seq.add(ASN1Integer(qInv));                   // qInv

    return seq.encodedBytes;
  }
}