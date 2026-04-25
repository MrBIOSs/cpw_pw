import 'dart:io';
import '../utils/ansi_colors.dart';
import 'command_info.dart';

/// Command registry with dynamic registration support and generated result.
final class CommandRegistry {
  final List<CommandInfo> _commands = [];

  /// Registers the command in the registry.
  void register(CommandInfo command) {
    assert(
    _commands.any((c) => c.name == command.name) == false,
    'Command "${command.name}" already registered.',
    );
    _commands.add(command);
  }

  /// Returns the command by name, or `null` if not found.
  CommandInfo? find(String name) {
    final results = _commands.where((c) => c.name == name);
    return results.isEmpty ? null : results.first;
  }

  void printMenu({
    String executableName = './cpw',
    bool useColors = true,
  }) {
    final pad = _calculatePadding(executableName);

    stdout.writeln(useColors ? AnsiColors.heading('Usage:') : 'Usage:');
    stdout.writeln();

    for (final cmd in _commands) {
      final name = cmd.usage ?? '$executableName ${cmd.name}';
      final desc = cmd.description;
      final padding = ' ' * (pad - name.length);

      if (useColors && stdout.supportsAnsiEscapes) {
        stdout.write(AnsiColors.command('\t$name'));
        stdout.write('$padding\t');
        stdout.writeln(AnsiColors.description(desc));
      } else {
        stdout.writeln('\t$name$padding\t$desc');
      }
    }
    stdout.writeln();
  }

  void printError(String message) {
    final useColors = stdout.supportsAnsiEscapes;
    stderr.writeln(useColors ? AnsiColors.error(message) : message);
  }

  /// Calculates the maximum width for the alignment.
  int _calculatePadding(String executable) {
    final names = _commands.map((c) => c.usage ?? '$executable ${c.name}');
    return names.map((n) => n.length).reduce((a, b) => a > b ? a : b);
  }
}