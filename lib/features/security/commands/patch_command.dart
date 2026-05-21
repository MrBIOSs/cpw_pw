import 'dart:io';
import '../../../core/utils/ansi_colors.dart';
import '../../../di/service_locator.dart' as di;
import '../security.dart';

/// Command "./cpw x [executable]".
final class PatchCommand {
  Future<int> execute({required List<String> args}) async {
    if (args.isEmpty) {
      stderr.writeln(AnsiColors.error('Missing executable path'));
      stderr.writeln(AnsiColors.dim('Usage: ./cpw x <path-to-executable> [--marker="..."] [--help]'));
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

      stdout.writeln(AnsiColors.heading('Patching executable...'));
      stdout.writeln(AnsiColors.dim('  File: $executablePath'));
      stdout.writeln(AnsiColors.dim('  Marker: "$marker"'));
      if (isHelp) stdout.writeln(AnsiColors.dim('  Mode: HELP RUN'));
      stdout.writeln();

      final result = await patcher.patchExecutable(
        executablePath: executablePath,
        marker: marker,
        isHelp: isHelp,
        verify: !isHelp,
      );

      stdout.writeln(AnsiColors.success('Executable patched successfully'));
      stdout.writeln(AnsiColors.dim('  Offset: ${result.markerOffset}'));
      stdout.writeln(AnsiColors.dim('  Key size: ${result.keySize} bytes (padded to ${result.originalSize})'));

      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln(AnsiColors.error('File error: ${e.message}'));
      return 1;
    } on StateError catch (e) {
      stderr.writeln(AnsiColors.error('$e'));
      stderr.writeln(AnsiColors.dim('Tip: Ensure the executable contains the exact marker string.'));
      return 1;
    } on Exception catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}