import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/patcher_config.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';

/// Environment validator before the idea.
class SetupValidator {
  SetupValidator(this._config);

  final PatcherConfig _config;

  /// Checks all requirements before starting the installation.
  /// Returns a list of errors (empty = OK).
  Future<List<String>> validate() async {
    final errors = <String>[];

    log.info('Validating environment...');
    if (!await _isWritable(_config.baseDir)) {
      errors.add('No write permission to base directory: ${_config.baseDir}');
    }
    await _validatePaths(errors);

    log.info('Environment validated');
    return errors;
  }

  Future<bool> _isWritable(String pathDir) async {
    try {
      final dir = Directory(pathDir);
      if (!dir.existsSync()) return false;

      final testFile = File(path.join(pathDir, '.write_test_${DateTime.now().microsecondsSinceEpoch}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _validatePaths(List<String> errors) async {
    final basePath = _config.patchPath;
    final paths = [
      basePath,
      path.join(basePath, _config.patchNewDir),
      path.join(basePath, _config.patchCpwDir),
    ];

    for (final relativePath in paths) {
      final fullPath = _config.resolvePath(relativePath);
      final dir = Directory(fullPath);

      if (!dir.existsSync()) {
        try {
          await dir.create(recursive: true);
          log.fine('Created directory: $fullPath');
        } on FileSystemException catch (e) {
          errors.add('Cannot create directory "$fullPath": $e');
        }
      } else if (!await _isWritable(dir.path)) {
        errors.add('Directory not writable: $fullPath');
      }
    }
  }
}