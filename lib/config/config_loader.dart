import 'dart:io';
import 'package:path/path.dart' as path;
import 'patcher_config.dart';
import 'config_parser.dart';

/// Configuration loader with support for:
/// 1. Reading from the `.conf` file
/// 2. Overriding via environment variables (Docker)
/// 3. Validating types and required fields
final class ConfigLoader {
  /// Loads and validates the configuration.
  /// [configPath] - path to the file (default: `config/patcher.conf` from CWD)
  static Future<PatcherConfig> load({String? configPath}) async {
    final currentPath = configPath ?? path.join(Directory.current.path, 'config', 'patcher.conf');
    final raw = await ConfigParser.parseFile(currentPath);

    _applyEnvOverrides(raw);

    return _buildAndValidate(raw);
  }

  /// Applies environment variables over values from a file.
  /// Format: `CPW_<KEY_UPPER_SNAKE>`
  static void _applyEnvOverrides(Map<String, String> config) {
    const envMap = {
      'DB_HOST': 'mysql-host',
      'DB_NAME': 'mysql-db',
      'DB_USER': 'mysql-user',
      'DB_PASSWORD': 'mysql-password',
      'CPW_DB_HOST': 'db-host',
      'CPW_DB_USER': 'db-user',
      'CPW_DB_PASSWORD': 'db-password',
      'CPW_DB_NAME': 'db-name',
      'CPW_RSA_PRIVATE_KEY': 'rsa-private-key',
      'CPW_RSA_PUBLIC_KEY': 'rsa-public-key',
      'CPW_PATCH_PATH': 'patch-path',
    };

    for (final envVar in envMap.entries) {
      final envVal = Platform.environment[envVar.key];
      if (envVal != null && envVal.isNotEmpty) {
        config[envVar.value] = envVal;
      }
    }
  }

  /// Builds a typed config with validation.
  static PatcherConfig _buildAndValidate(Map<String, String> raw) {
    T get<T>(
        String key, {
          required T Function(String) parse,
          T? defaultValue,
        }) {
      final val = raw[key]?.trim();
      if (val == null || val.isEmpty) {
        if (defaultValue != null) return defaultValue;
        throw StateError('Missing required config key: "$key"');
      }
      try {
        return parse(val);
      } catch (e) {
        throw FormatException('Invalid config value for "$key": "$val". Error: $e');
      }
    }

    // Parsing Boolean flags: true/false/yes/no/1/0
    bool parseBool(String s) => switch (s.toLowerCase()) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => throw FormatException('Expected boolean, got "$s"'),
    };

    return PatcherConfig(
      // RSA
      rsaPrivateKey: get('rsa-private-key', parse: (s) => s),
      rsaPublicKey: get('rsa-public-key', parse: (s) => s),
      rsaModulus: get('rsa-modus', parse: BigInt.parse),
      rsaPrivateExponent: get('rsa-private-x', parse: BigInt.parse),
      rsaPublicExponent: get('rsa-public-x', parse: BigInt.parse),

      // DB
      dbHost: get('db-host', parse: (s) => s, defaultValue: 'localhost'),
      dbUser: get('db-user', parse: (s) => s),
      dbPassword: get('db-password', parse: (s) => s),
      dbName: get('db-name', parse: (s) => s),

      // Paths
      patchPath: get('patch-path', parse: (s) => s, defaultValue: 'files'),
      patchNewDir: get('patch-new-dir', parse: (s) => s, defaultValue: 'new'),
      patchCpwDir: get('patch-cpw-dir', parse: (s) => s, defaultValue: 'CPW'),

      // Versions
      minLauncherVer: get('min-launcher-ver', parse: int.parse, defaultValue: 1),
      minPatcherVer: get('min-patcher-ver', parse: int.parse, defaultValue: 1),
      minElementVer: get('min-element-ver', parse: int.parse, defaultValue: 1),

      // Flags
      removeFolders: get('remove-folders', parse: parseBool, defaultValue: true),
      removeFiles: get('remove-files', parse: parseBool, defaultValue: true),
      addSize: get('add-size', parse: parseBool, defaultValue: true),
    );
  }
}