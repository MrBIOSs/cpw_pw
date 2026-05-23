import 'dart:io';
import 'package:cpw_pw/core/utils/ansi_colors.dart';
import 'package:cpw_pw/di/service_locator.dart' as di;
import 'package:cpw_pw/features/security/security.dart';

/// Command "./cpw x".
final class PatchCommand {
  Future<int> execute({required List<String> args}) async {
    if (args.isEmpty) {
      stderr
        ..writeln(AnsiColors.error('Missing executable path'))
        ..writeln(AnsiColors.dim('Usage: ./cpw x <path-to-executable> [--marker="..."] [--help]'));
      return 1;
    }

    final executablePath = args[0];
    final markerArg = args.firstWhere((a) => a.startsWith('--marker='), orElse: () => '');
    final marker = markerArg.isNotEmpty
        ? markerArg.substring('--marker='.length)
        : '-----BEGIN PUBLIC KEY-----';
    final isHelp = args.contains('--help') || args.contains('-h');

    try {
      final patcher = di.getIt<BinaryPatcherService>();

      stdout
        ..writeln(AnsiColors.heading('Patching executable...'))
        ..writeln(AnsiColors.dim('  File: $executablePath'))
        ..writeln(AnsiColors.dim('  Marker: "$marker"'));
      if (isHelp) stdout.writeln(AnsiColors.dim('  Mode: HELP RUN'));
      stdout.writeln();

      final result = await patcher.patchExecutable(
        executablePath: executablePath,
        marker: marker,
        isHelp: isHelp,
        verify: !isHelp,
      );

      stdout
        ..writeln(AnsiColors.success('Executable patched successfully'))
        ..writeln(AnsiColors.dim('  Offset: ${result.markerOffset}'))
        ..writeln(AnsiColors.dim('  Key size: ${result.keySize} bytes (padded to ${result.originalSize})'));

      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln(AnsiColors.error('File error: ${e.message}'));
      return 1;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}