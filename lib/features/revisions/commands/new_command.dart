import 'dart:io';
import '../../../core/database/database.dart';
import '../../../core/utils/ansi_colors.dart';
import '../../../di/service_locator.dart' as di;
import '../revisions.dart';

/// Command "./cpw new".
final class NewCommand {
  Future<int> execute({required List<String> args}) async {
    final force = args.contains('--force');
    final help = args.contains('--help') || args.contains('-h');
    final skipManifests = args.contains('--skip-manifests');

    if (help) {
      stdout.writeln(AnsiColors.heading('Help — next revision'));
      stdout.writeln(AnsiColors.dim('  - Pack files: files/new/* to files/CPW/*'));
      stdout.writeln(AnsiColors.dim('  - Update database metadata'));
      stdout.writeln(AnsiColors.dim('  - Increment revision: current + 1'));
      stdout.writeln(AnsiColors.dim('  - Generate manifests: files.md5, v-N.inc'));

      return 0;
    }

    if (force) {
      stdout.writeln(AnsiColors.warning(
        'Force mode: will overwrite files from a potentially failed previous run.',
      ));
      stdout.write('Continue? [y/N]: ');
      if ((stdin.readLineSync()?.trim().toLowerCase()) != 'y') {
        stdout.writeln('Aborted.');
        return 0;
      }
      stdout.writeln();
    }

    try {
      final revisionService = di.getIt<RevisionService>();
      final manifestService = di.getIt<ManifestService>();

      stdout.writeln(AnsiColors.heading('Creating next revision...'));
      stdout.writeln();

      await revisionService.syncVersionFilesToDb();
      final state = await revisionService.createNext(force: force);
      stdout.writeln(AnsiColors.success('  Files packed & database updated'));

      if (!skipManifests) {
        stdout.writeln(AnsiColors.dim('  Generating manifests...'));
        for (final type in ['element', 'launcher', 'patcher']) {
          await manifestService.generateManifests(type, state);
        }
        stdout.writeln(AnsiColors.success('  Manifests generated & signed'));
      }

      stdout.writeln();
      stdout.writeln(AnsiColors.success('Revision published successfully!'));
      stdout.writeln();
      stdout.writeln(AnsiColors.heading('New revision state:'));
      stdout.writeln('  element:   v${state.elementCurrentVer}');
      stdout.writeln('  launcher:  v${state.launcherCurrentVer}');
      stdout.writeln('  patcher:   v${state.patcherCurrentVer}');
      stdout.writeln();
      stdout.writeln(AnsiColors.dim('Clients can now update to this revision.'));

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