import 'dart:io';
import '../config/config.dart';
import '../features/security/commands/rsagen_command.dart';
import 'command_registry.dart';

/// Initializes the command registry and processes command-line arguments.
/// Returns an exit code: 0 = success, 64 = invalid use, 1 = error.
Future<int> runCli(
    List<String> args,
    PatcherConfig config,
    String baseDir
    ) async {
  final registry = _buildCommandRegistry(config, baseDir);

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
  return await command.action(args.skip(1).toList(), config, baseDir);
}

/// Registers all available commands.
CommandRegistry _buildCommandRegistry(PatcherConfig config, String baseDir) {
  final registry = CommandRegistry();

  registry.register((
  name: 'install',
  description: 'install updater: database setup, rsa keys generation, paths.',
  usage: null,
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'rsagen',
  description: 'regenerate rsa keys',
  usage: null,
  action: (args, cfg, dir) => RsagenCommand().execute(
    args: args,
    config: cfg,
    baseDir: dir,
  )));

  registry.register((
  name: 'x',
  description: 'patches executable with public rsa key',
  usage: './cpw x [executable]',
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'initial',
  description: 'creates initial (base) revision, doesn\'t creates lists',
  usage: null,
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'new',
  description: 'creates next or given revision, creates lists',
  usage: './cpw new [revision number]',
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'revision',
  description: '',
  usage: './cpw revision [revision number]',
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'listgen',
  description: '',
  usage: null,
  action: (args, cfg, dir) async => 0,
  ));

  registry.register((
  name: 'listupdate',
  description: 'update lists only',
  usage: null,
  action: (args, cfg, dir) async => 0,
  ));

  return registry;
}