import 'dart:io';
import 'package:cpw_pw/config/patcher_config.dart';
import 'package:cpw_pw/core/utils/ansi_colors.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/features/revisions/revisions.dart';

/// Command "./cpw initial".
final class InitialCommand {
  final PatcherConfig _config = di.getIt<PatcherConfig>();

  Future<int> execute({required List<String> args}) async {
    final isHelp = args.contains('--help') || args.contains('-h');

    if (isHelp) {
      stdout
        ..writeln(AnsiColors.heading('Help mode — no changes will be made'))
        ..writeln();
    }

    try {
      final revisionService = di.getIt<RevisionService>();
      final manifestService = di.getIt<ManifestService>();

      stdout
        ..writeln(AnsiColors.heading('Creating initial revision...'))
        ..writeln();

      if (isHelp) {
        final state = revisionService.getInitialState;
        stdout
          ..writeln(AnsiColors.dim('Would initialize:'))
          ..writeln(AnsiColors.dim('  - element:   revision ${state.elementCurrentVer}'))
          ..writeln(AnsiColors.dim('  - launcher:  revision ${state.launcherCurrentVer}'))
          ..writeln(AnsiColors.dim('  - patcher:   revision ${state.patcherCurrentVer}'))
          ..writeln(AnsiColors.dim('  - DB:   resetting "files" table'))
          ..writeln()
          ..writeln(AnsiColors.dim('Would create directories:'))
          ..writeln(AnsiColors.dim('  - info/pid'));
        for (final type in ['element', 'launcher', 'patcher']) {
          stdout
            ..writeln(AnsiColors.dim('  - ${_config.resolveSubDir(_config.patchCpwDir, type)}/'))
            ..writeln(AnsiColors.dim('  - ${_config.resolveSubDir(_config.patchNewDir, type)}/'));
        }
        stdout.writeln();
        return 0;
      }

      final state = await revisionService.createInitial();

      stdout.writeln(AnsiColors.dim('Generating manifests...'));
      for (final type in ['element', 'launcher', 'patcher']) {
        await manifestService.generateManifests(type, state, isInitial: true);
      }
      stdout
        ..writeln(AnsiColors.success('Manifests generated & signed'))
        ..writeln(AnsiColors.success('Initial revision created successfully!'))
        ..writeln()
        ..writeln(AnsiColors.heading('Revision details:'))
        ..writeln('  element:   ${AnsiColors.command(state.elementCurrentVer)}')
        ..writeln('  launcher:  ${AnsiColors.command(state.launcherCurrentVer)}')
        ..writeln('  patcher:   ${AnsiColors.command(state.patcherCurrentVer)}')
        ..writeln()
        ..writeln(AnsiColors.dim('Next steps:'))
        ..writeln(AnsiColors.dim('  - On the original client, check /patcher/server/pid.ini for the correct version (default 101)'))
        ..writeln(AnsiColors.dim('  - Add files to files/new/{element,launcher,patcher}/'))
        ..writeln(AnsiColors.dim('  - Run "./cpw new" to pack files and generate manifests'))
        ..writeln(AnsiColors.dim('  - Run "./cpw listgen" to regenerate files.md5 only'));

      return 0;

    } on FileSystemException catch (e) {
      stderr.writeln(AnsiColors.error('File system error: $e'));
      return 1;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}