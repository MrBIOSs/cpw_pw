import 'dart:io';
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/core/utils/ansi_colors.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/features/setup/setup_service.dart';

/// Command "./cpw install".
final class InstallCommand {
  Future<int> execute({ required List<String> args }) async {
    final skipDb = args.contains('--skip-db');
    final skipKeys = args.contains('--skip-keys');
    final isHelp = args.contains('--help') || args.contains('-h');

    if (isHelp) {
      stdout
        ..writeln(AnsiColors.heading('Help mode - no changes will be made'))
        ..writeln();
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

      stdout
        ..writeln(AnsiColors.heading('Starting installation...'))
        ..writeln();

      if (isHelp) {
        stdout
          ..writeln(AnsiColors.dim('This command does:'))
          ..writeln(AnsiColors.dim('  - Connects to the database.'))
          ..writeln(AnsiColors.dim('  - Runs the install script if any required tables are missing.'))
          ..writeln(AnsiColors.dim('  - Generates new 1024-bit RSA keys if they do not exist.'))
          ..writeln();
        return 0;
      }

      final result = await setupService.initialize(
        skipKeys: skipKeys,
        skipDb: skipDb,
      );

      stdout.writeln();
      var currentStep = 1;
      for (final step in result.steps) {
        stdout.writeln(AnsiColors.success('[$currentStep/${result.steps.length}] $step'));
        currentStep++;
      }

      if (result.errors.isNotEmpty) {
        stderr
          ..writeln()
          ..writeln(AnsiColors.error('Installation failed:'));
        for (final error in result.errors) {
          stderr.writeln(AnsiColors.dim('- $error'));
        }
        return 1;
      }

      stdout.writeln();
      if (result.isSuccess) {
        stdout
          ..writeln(AnsiColors.success('Installation completed successfully!'))
          ..writeln()
          ..writeln(AnsiColors.dim('Next steps:'))
          ..writeln(AnsiColors.dim('  - Run "./cpw initial" to create base revision'));
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