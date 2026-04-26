import 'dart:io';

/// Parses `.conf` files.
/// Supports:
/// - `key=value` format
/// - `#` and `!` comments
/// - Empty lines
/// - Spaces around `=`
final class ConfigParser {
  /// Returns a key-value map from the contents of the config.
  static Map<String, String> parse(String content) {
    final map = <String, String>{};

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) {
        continue;
      }

      final eqIndex = trimmed.indexOf('=');
      if (eqIndex == -1) continue;

      final key = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();

      if (key.isNotEmpty) {
        map[key] = value;
      }
    }
    return map;
  }

  /// Reads a file and parses its contents.
  static Future<Map<String, String>> parseFile(String filePath) async {
    final file = File(filePath);

    if (!file.existsSync()) {
      throw FileSystemException('Configuration file not found', filePath);
    }
    return parse(await file.readAsString());
  }
}