import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';
import 'package:cpw_pw/services/logger_service.dart';

Future<void> main(List<String> arguments) async {
  final logDir = path.join(_getProjectRoot(), 'log');

  final loggerService = LoggerService(logDir: logDir);

  await loggerService.initialize();

  final log = Logger('App');
  log.info('CPW Patcher started');

  try {
    await runCli(arguments);
    log.info('Completed successfully');
  } catch (e, st) {
    log.severe('Unhandled error', e, st);
  } finally {
    await loggerService.dispose();
  }
}

Future<void> runCli(List<String> args) async {
  throw Exception('Test bug');
}

/// Defines the root directory of the project.
/// Returns the current directory during development (Dart Run)
/// or the directory containing the binary when running the compiled file.
String _getProjectRoot() {
  final exePath = Platform.resolvedExecutable;
  final exeName = path.basenameWithoutExtension(exePath).toLowerCase();

  if (exeName == 'dart') {
    return Directory.current.path;
  } else {
    return path.dirname(exePath);
  }
}