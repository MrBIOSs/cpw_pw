import 'dart:convert';

/// Features:
/// - Replaces '/' with '-' in the result (for URL-safe)
final class Base64PathEncoder {
  const Base64PathEncoder._();

  /// Encodes the full relative path.
  /// Example: 'data/config.ini' to 'ZGF0YV9jb25maWcuaW5p'
  static String encode(String relativePath) {
    if (relativePath.isEmpty) return '';

    final bytes = utf8.encode(relativePath);
    final base64 = base64Encode(bytes);
    return base64.replaceAll('/', '-').replaceAll('+', '_');
  }

  static String decode(String encoded) {
    if (encoded.isEmpty) return '';

    final base64 = encoded.replaceAll('-', '/').replaceAll('_', '+');
    final bytes = base64Decode(base64);
    return utf8.decode(bytes);
  }
}