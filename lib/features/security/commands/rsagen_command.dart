import 'dart:io';
import '../../../core/crypto/crypto.dart';
import '../../../core/utils/ansi_colors.dart';
import '../../../di/service_locator.dart' as di;
import '../security.dart';

/// Command "./cpw rsagen": regenerate RSA keys.
final class RsagenCommand {
  /// Returns exit code: 0 = success, 1 = error.
  Future<int> execute({ required List<String> args }) async {
    final rsaService = di.getIt<RsaService>();

    if (rsaService.hasKeys()) {
      stdout.writeln(AnsiColors.warning(
        'RSA keys already exist.',
      ));
      stdout.write('Regenerate anyway? [y/N]: ');

      final response = stdin.readLineSync()?.trim().toLowerCase();
      if (response != 'y' && response != 'yes') {
        stdout.writeln('Aborted.');
        return 0;
      }
    }

    try {
      final keyPair = await rsaService.generateAndSave();

      stdout.writeln();
      stdout.writeln(AnsiColors.heading('Generated Public Key:'));
      stdout.writeln(AnsiColors.dim('─' * 60));
      stdout.writeln(RsaService.formatPublicKeyForCopy(keyPair));
      stdout.writeln(AnsiColors.dim('─' * 60));
      stdout.writeln();

      stdout.writeln(AnsiColors.success(
        'Keys saved to config/keys.json',
      ));
      stdout.writeln(AnsiColors.dim(
        'Tip: Set file permissions to 600 for security: chmod 600 config/keys.json',
      ));

      return 0;
    } on KeyGenerationException catch (e) {
      stderr.writeln(AnsiColors.error('Key generation failed: $e'));
      return 1;
    } on KeyStorageException catch (e) {
      stderr.writeln(AnsiColors.error('Failed to save keys: $e'));
      return 1;
    } catch (e) {
      stderr.writeln(AnsiColors.error('Unexpected error: $e'));
      return 1;
    }
  }
}