import 'dart:convert';
import 'dart:typed_data';

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

  /// Converts BigInt to bytes (big-endian, unsigned).
  static Uint8List _bigIntToBytes(BigInt number) {
    final int bytes = (number.bitLength + 7) >> 3;
    final b256 = BigInt.from(256);
    final result = Uint8List(bytes);

    for (int i = 0; i < bytes; i++) {
      result[bytes - 1 - i] = number.remainder(b256).toInt();
      number = number >> 8;
    }
    return result;
  }

  /// Converts bytes to BigInt (big-endian, unsigned).
  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.from(0);
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }
}