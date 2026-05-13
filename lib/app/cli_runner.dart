import 'dart:io';
import '../di/service_locator.dart';
import 'command_registry.dart';

/// Initializes the command registry and processes command-line arguments.
/// Returns an exit code: 0 = success, 64 = invalid use, 1 = error.
Future<int> runCli(List<String> args) async {
  final registry = getIt<CommandRegistry>();

  if (args.isEmpty) {
    registry.printMenu();
    return 0;
  }

  final commandName = args[0];
  final command = registry.find(commandName);

  if (command == null) {
    registry.printError('Unknown command: $commandName');
    stderr.writeln();
    registry.printMenu();
    return 64;
  }
  return await command.action(args.skip(1).toList());
}