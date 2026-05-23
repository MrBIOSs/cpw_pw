import 'dart:io';
import 'package:cpw_pw/core/utils/ansi_colors.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/features/revisions/revisions.dart';

/// Command "./cpw listgen".
/// Regenerates manifests from the current state of the database without incrementing the revision.
final class ListgenCommand {
  Future<int> execute({required List<String> args}) async {
    final type = _parseTypeArg(args);
    final isHelp = args.contains('--help') || args.contains('-h');

    if (isHelp) {
      stdout
        ..writeln(AnsiColors.heading('Help — regenerate manifests only'))
        ..writeln(AnsiColors.dim('  - Read current state from DB/files'))
        ..writeln(AnsiColors.dim('  - Rebuild files.md5 & v-N.inc'))
        ..writeln(AnsiColors.dim('  - Sign with RSA'));
      return 0;
    }

    try {
      final revisionService = di.getIt<RevisionService>();
      final manifestService = di.getIt<ManifestService>();

      await revisionService.syncVersionFilesToDb();
      final state = await revisionService.getCurrentState();

      stdout
        ..writeln(AnsiColors.heading('Regenerating manifests from current DB state...'))
        ..writeln();

      final types = type != null ? [type] : ['element', 'launcher', 'patcher'];

      for (final t in types) {
        stdout.writeln(AnsiColors.dim('  - $t: reading DB & rebuilding...'));
        await manifestService.generateManifests(t, state);
        stdout.writeln(AnsiColors.success('    $t: done'));
      }

      stdout
        ..writeln()
        ..writeln(AnsiColors.success('Manifests regenerated successfully!'))
        ..writeln(AnsiColors.dim('Tip: If you only modified files, use "./cpw new" to pack & increment.'));

      return 0;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Failed: $e'));
      return 1;
    }
  }

  String? _parseTypeArg(List<String> args) {
    final arg = args.firstWhere((a) => a.startsWith('--type='), orElse: () => '');
    if (arg.isEmpty) return null;
    final type = arg.substring(7).toLowerCase();
    if (!['element', 'launcher', 'patcher'].contains(type)) {
      throw ArgumentError('Unknown type: $type. Use element, launcher, or patcher.');
    }
    return type;
  }
}