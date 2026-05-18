import 'dart:io';
import '../../../config/config.dart';
import '../../../core/database/database.dart';
import '../../../core/utils/ansi_colors.dart';
import '../../../di/service_locator.dart' as di;
import '../../security/security.dart';
import '../setup_service.dart';

/// Command "./cpw install".
final class InstallCommand {
  Future<int> execute({ required List<String> args }) async {
    final skipDb = args.contains('--skip-db');
    final skipKeys = args.contains('--skip-keys');
    final help = args.contains('--help') || args.contains('-h');

    if (help) {
      stdout.writeln(AnsiColors.heading('Help mode — no changes will be made'));
      stdout.writeln();
    }

    try {
      final dbService = di.getIt<DbService>();
      final rsaService = di.getIt<RsaService>();
      final config = di.getIt<PatcherConfig>();
      final setupService = SetupService(
        dbService: dbService,
        rsaService: rsaService,
        config: config,
      );

      stdout.writeln(AnsiColors.heading('Starting installation...'));
      stdout.writeln();

      if (help) {
        stdout.writeln(AnsiColors.dim('This command does:'));
        stdout.writeln(AnsiColors.dim('  - Connects to the database.'));
        stdout.writeln(AnsiColors.dim('  - Runs the install script if any required tables are missing.'));
        stdout.writeln(AnsiColors.dim('  - Generates new 2048-bit RSA keys if they do not exist.'));

        stdout.writeln();
        return 0;
      }

      final result = await setupService.initialize(
        skipKeys: skipKeys,
        skipDb: skipDb,
      );

      stdout.writeln();
      int currentStep = 1;
      for (final step in result.steps) {
        stdout.writeln(AnsiColors.success('[$currentStep/${result.steps.length}] $step'));
        currentStep++;
      }

      if (result.errors.isNotEmpty) {
        stderr.writeln();
        stderr.writeln(AnsiColors.error('Installation failed:'));
        for (final error in result.errors) {
          stderr.writeln(AnsiColors.dim('- $error'));
        }
        return 1;
      }

      stdout.writeln();
      if (result.isSuccess) {
        stdout.writeln(AnsiColors.success('Installation completed successfully!'));
        stdout.writeln();
        stdout.writeln(AnsiColors.dim('Next steps:'));
        stdout.writeln(AnsiColors.dim('  - Run "./cpw initial" to create base revision'));
      } else {
        stdout.writeln(AnsiColors.warning('Installation completed with warnings'));
      }

      return result.isSuccess ? 0 : 1;

    } on FileSystemException catch (e) {
      stderr.writeln(AnsiColors.error('File system error: $e'));
      return 1;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}