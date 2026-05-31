import 'dart:io';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/core/utils/ansi_colors.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/features/revisions/revisions.dart';

/// Command "./cpw new".
final class NewCommand {
  Future<int> execute({required List<String> args}) async {
    final isForce = args.contains('--force');
    final isHelp = args.contains('--help') || args.contains('-h');
    final skipManifests = args.contains('--skip-manifests');

    if (isHelp) {
      stdout
        ..writeln(AnsiColors.heading('Help — next revision'))
        ..writeln(AnsiColors.dim('  - Pack files: files/new/* to files/CPW/*'))
        ..writeln(AnsiColors.dim('  - Update database metadata'))
        ..writeln(AnsiColors.dim('  - Increment revision: current + 1'))
        ..writeln(AnsiColors.dim('  - Generate manifests: files.md5, v-N.inc'))
        ..writeln(AnsiColors.dim('  - Remove input files if remove-input-files = true.'));

      return 0;
    }

    if (isForce) {
      stdout
        ..writeln(AnsiColors.warning(
          'Force mode: will overwrite files from a potentially failed previous run.',
        ))
        ..write('Continue? [y/N]: ');
      if (stdin.readLineSync()?.trim().toLowerCase() != 'y') {
        stdout.writeln('Aborted.');
        return 0;
      }
      stdout.writeln();
    }

    try {
      final revisionService = di.getIt<RevisionService>();
      final manifestService = di.getIt<ManifestService>();

      stdout
        ..writeln(AnsiColors.heading('Creating next revision...'))
        ..writeln();

      final state = await revisionService.createNext(force: isForce);
      stdout.writeln(AnsiColors.success('  Files packed & database updated'));

      if (!skipManifests) {
        stdout.writeln(AnsiColors.dim('  Generating manifests...'));
        for (final type in ['element', 'launcher', 'patcher']) {
          await manifestService.generateManifests(type, state);
        }
        stdout.writeln(AnsiColors.success('  Manifests generated & signed'));
      }

      stdout
        ..writeln()
        ..writeln(AnsiColors.success('Revision published successfully!'))
        ..writeln()
        ..writeln(AnsiColors.heading('New revision state:'))
        ..writeln('  element:   v${state.elementCurrentVer}')
        ..writeln('  launcher:  v${state.launcherCurrentVer}')
        ..writeln('  patcher:   v${state.patcherCurrentVer}')
        ..writeln()
        ..writeln(AnsiColors.dim('Clients can now update to this revision.'));

      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln(AnsiColors.error('File system error: $e'));
      return 1;
    } on DatabaseException catch (e) {
      stderr.writeln(AnsiColors.error('Database error: $e'));
      return 1;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}