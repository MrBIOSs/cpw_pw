import 'dart:convert';

/// Features:
/// - Removes all slashes from the string before encoding
/// - Doesn't add '=' padding
/// - Replaces '/' with '-' in the result (for URL-safe)
final class Base64PathEncoder {
  const Base64PathEncoder._();

  /// Encodes the full relative path.
  /// Example: 'data/config.ini' to 'ZGF0YV9jb25maWcuaW5p'
  static String encode(String relativePath) {
    final clean = relativePath.replaceAll(r'\', '/').replaceAll('/', '');
    if (clean.isEmpty) return '';

    final bytes = utf8.encode(clean);
    final base64 = base64Encode(bytes).replaceAll(RegExp(r'=+$'), '');
    return base64.replaceAll('/', '-');
  }

  /// Encodes the file name only.
  static String encodeFileName(String fileName) => encode(fileName);

  /// Encodes only the folder.
  static String encodeFolder(String folder) => encode(folder);

  static String decode(String encoded) {
    final base64 = encoded.replaceAll('-', '/');
    final padded = base64 + '=' * (4 - base64.length % 4);
    final bytes = base64Decode(padded);
    return utf8.decode(bytes);
  }
}