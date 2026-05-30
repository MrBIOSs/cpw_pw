import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/asymmetric/api.dart';

final class RsaUtils {
  const RsaUtils._();

  /// Encodes BigInt to Base64 without padding.
  static String bigIntToBase64(BigInt value) {
    final bytes = _bigIntToBytes(value);
    return base64.encode(bytes).replaceAll('=', '');
  }

  /// Decodes Base64 to BigInt.
  static BigInt base64ToBigInt(String encoded) {
    final padded = encoded + '=' * (4 - encoded.length % 4);
    final bytes = base64.decode(padded);
    return _bytesToBigInt(bytes);
  }

  /// Generates a PEM string from DER-encoded data.
  static String toPem(String label, Uint8List der) {
    final base64 = base64Encode(der);
    final lines = <String>['-----BEGIN $label-----'];

    for (var i = 0; i < base64.length; i += 64) {
      lines.add(base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }

    lines.add('-----END $label-----');
    return lines.join('\n');
  }

  /// Calculates the modular inverse: (a^-1) mod m.
  /// Uses the extended Euclidean algorithm.
  static BigInt modInverse(BigInt a, BigInt m) {
    final m0 = m;
    var y = BigInt.one;
    var x = BigInt.zero;
    var aa = a;
    var mm = m;

    while (aa > BigInt.one) {
      final q = aa ~/ mm;
      final t = mm;

      mm = aa % mm;
      aa = t;

      final temp = x;
      x = y - q * x;
      y = temp;
    }

    if (y < BigInt.zero) y += m0;
    return y;
  }

  /// Encodes the public key in DER (SubjectPublicKeyInfo).
  /// Structure:
  /// SEQUENCE {
  ///   SEQUENCE { algorithm OID, NULL }
  ///   BIT STRING { SEQUENCE { modulus INTEGER, exponent INTEGER } }
  /// }
  static Uint8List encodeSubjectPublicKeyInfo(RSAPublicKey key) {
    final rsaSeq = ASN1Sequence()
      ..add(ASN1Integer(key.modulus!))
      ..add(ASN1Integer(key.exponent!));

    final rsaSeqBytes = rsaSeq.encodedBytes;
    final bitStringContent = Uint8List(rsaSeqBytes.length + 1);
    bitStringContent[0] = 0x00;
    bitStringContent.setAll(1, rsaSeqBytes);

    final bitStringContainer = ASN1OctetString(bitStringContent);
    final bitStringBytes = bitStringContainer.encodedBytes;

    bitStringBytes[0] = 0x03;

    final algoSeq = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'))
      ..add(ASN1Null());

    final spki = ASN1Sequence()
      ..add(algoSeq);

    final spkiHeader = spki.encodedBytes;
    final parser = ASN1Parser(spkiHeader);
    final topLevelSeq = parser.nextObject() as ASN1Sequence;

    final customBitString = ASN1Object.fromBytes(bitStringBytes);
    topLevelSeq.add(customBitString);

    return topLevelSeq.encodedBytes;
  }

  /// Encodes the private key in DER (RSAPrivateKey, PKCS#1).
  /// Structure:
  /// SEQUENCE {
  ///   version INTEGER,
  ///   modulus INTEGER, publicExponent INTEGER, privateExponent INTEGER,
  ///   prime1 INTEGER, prime2 INTEGER,
  ///   exponent1 INTEGER, exponent2 INTEGER, coefficient INTEGER
  /// }
  static Uint8List encodeRsaPrivateKey(RSAPrivateKey key) {
    final p = key.p!;
    final q = key.q!;
    final dP = key.privateExponent! % (p - BigInt.one); // d mod (p-1)
    final dQ = key.privateExponent! % (q - BigInt.one); // d mod (q-1)
    final qInv = RsaUtils.modInverse(q, p); // q^-1 mod p
    final seq = ASN1Sequence()
      ..add(ASN1Integer(BigInt.zero))
      ..add(ASN1Integer(key.modulus!))           // n
      ..add(ASN1Integer(key.exponent!))          // e
      ..add(ASN1Integer(key.privateExponent!))   // d
      ..add(ASN1Integer(p))                      // p
      ..add(ASN1Integer(q))                      // q
      ..add(ASN1Integer(dP))                     // dP
      ..add(ASN1Integer(dQ))                     // dQ
      ..add(ASN1Integer(qInv));                  // qInv

    return seq.encodedBytes;
  }

  /// Converts BigInt to bytes (big-endian, unsigned).
  static Uint8List _bigIntToBytes(BigInt number) {
    final bytes = (number.bitLength + 7) >> 3;
    final b256 = BigInt.from(256);
    final result = Uint8List(bytes);

    for (var i = 0; i < bytes; i++) {
      result[bytes - 1 - i] = number.remainder(b256).toInt();
      number = number >> 8;
    }
    return result;
  }

  /// Converts bytes to BigInt (big-endian, unsigned).
  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.from(0);
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }
}