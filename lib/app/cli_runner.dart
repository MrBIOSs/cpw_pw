import 'dart:io';
import 'command_registry.dart';

/// Initializes the command registry and processes command-line arguments.
/// Returns an exit code: 0 = success, 64 = invalid use, 1 = error.
Future<int> runCli(List<String> args) async {
  final registry = _buildCommandRegistry();

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

  stdout.writeln('Executing: ${command.name}');
  stdout.writeln('   Args: ${args.skip(1).join(' ')}');

  return 0;
}

/// Registers all available commands.
CommandRegistry _buildCommandRegistry() {
  final registry = CommandRegistry();

  registry.register((
  name: 'install',
  description: 'install updater: database setup, rsa keys generation, paths.',
  usage: null,
  ));

  registry.register((
  name: 'rsagen',
  description: 'regenerate rsa keys',
  usage: null,
  ));

  registry.register((
  name: 'x',
  description: 'patches executable with public rsa key',
  usage: './cpw x [executable]',
  ));

  registry.register((
  name: 'initial',
  description: 'creates initial (base) revision, doesn\'t creates lists',
  usage: null,
  ));

  registry.register((
  name: 'new',
  description: 'creates next or given revision, creates lists',
  usage: './cpw new [revision number]',
  ));

  registry.register((
  name: 'revision',
  description: '',
  usage: './cpw revision [revision number]',
  ));

  registry.register((
  name: 'listgen',
  description: '',
  usage: null,
  ));

  registry.register((
  name: 'listupdate',
  description: 'update lists only',
  usage: null,
  ));

  return registry;
}