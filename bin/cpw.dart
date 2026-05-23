import 'dart:io';
import 'package:logging/logging.dart';
import 'package:cpw_pw/app/cli_runner.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/core/logger/logger_service.dart';

Future<void> main(List<String> arguments) async {
  LoggerService? loggerService;
  final log = Logger('App');

  try {
    await di.initServiceLocator();

    loggerService = di.getIt<LoggerService>();
    await loggerService.initialize();

    /// Clears buffers before exiting.
    Future<void> shutdown() async {
      await loggerService?.dispose();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) => shutdown());

    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => shutdown());
    }

    log.info('CPW Patcher started');

    final exitCode = await runCli(arguments);

    log.info('Exiting with code: $exitCode');
    exit(exitCode);
  } catch (e, st) {
    if (loggerService != null) {
      log.severe('Execution failed', e, st);
    } else {
      stderr.writeln('Startup failed: $e\n$st');
    }
    exit(1);
  } finally {
    await loggerService?.dispose();
  }
}