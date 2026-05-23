import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:cpw_pw/app/command_registry.dart';
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/core/crypto/crypto.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';
import 'package:cpw_pw/features/revisions/revisions.dart';
import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/features/setup/setup.dart';

/// Global service locator.
final GetIt getIt = GetIt.instance;

/// Initializes all application dependencies.
/// Called once in main() before running the logic.
Future<void> initServiceLocator({ String? configPath }) async {
  await _registerConfig(configPath: configPath);
  _registerLogger();
  _registerDatabase();
  _registerCrypto();
  _registerFeatures();
  _registerCommands();
}

Future<void> _registerConfig({ String? configPath }) async {
  final config = await ConfigLoader.load(configPath: configPath);

  Logger('App').info('The config was loaded successfully.');

  getIt.registerSingleton<PatcherConfig>(config);
}

void _registerLogger() {
  final baseDir = getIt<PatcherConfig>().baseDir;
  getIt.registerLazySingleton<LoggerService>(() => LoggerService(logDir: '$baseDir/log'));
}

void _registerDatabase() {
  final config = getIt<PatcherConfig>();

  getIt
    ..registerLazySingleton<IDatabase>(() => MysqlAdapter(config))
    ..registerLazySingleton<DbService>(() => DbService(
      config: config,
      adapter: getIt<IDatabase>(),
  ));
}

void _registerCrypto() {
  final baseDir = getIt<PatcherConfig>().baseDir;

  getIt
    ..registerLazySingleton<IKeyStorage>(() => FileKeyStorage(baseDir: baseDir))
    ..registerLazySingleton<RsaService>(() => RsaService(storage: getIt<IKeyStorage>()));
}

void _registerFeatures() {
  getIt
    ..registerLazySingleton<SetupService>(() => SetupService(
      dbService: getIt<DbService>(),
      rsaService: getIt<RsaService>(),
      config: getIt<PatcherConfig>(),
    ))
    ..registerLazySingleton<BinaryPatcherService>(
        () => BinaryPatcherService(keyStorage: getIt<IKeyStorage>()),
    )
    ..registerLazySingleton<PackerService>(PackerService.new)
    ..registerLazySingleton<RevisionService>(() => RevisionService(
      config: getIt<PatcherConfig>(),
      dbService: getIt<DbService>(),
      packer: getIt<PackerService>(),
    ))
    ..registerLazySingleton<ManifestService>(() => ManifestService(
      config: getIt<PatcherConfig>(),
      dbService: getIt<DbService>(),
      rsaService: getIt<RsaService>(),
    ));
}

void _registerCommands() {
  getIt
    ..registerFactory<InstallCommand>(InstallCommand.new)
    ..registerFactory<RsagenCommand>(RsagenCommand.new)
    ..registerFactory<PatchCommand>(PatchCommand.new)
    ..registerFactory<InitialCommand>(InitialCommand.new)
    ..registerFactory<NewCommand>(NewCommand.new)
    ..registerFactory<ListgenCommand>(ListgenCommand.new)
    ..registerSingleton<CommandRegistry>(_buildCommandRegistry());
}

/// Registers all available commands.
CommandRegistry _buildCommandRegistry() {
  final registry = CommandRegistry()
    ..register((
    name: 'install',
    description: 'Install updater: database setup, RSA keys generation, paths',
    usage: null,
    action: (args) async => getIt<InstallCommand>().execute(args: args)))

    ..register((
    name: 'rsagen',
    description: 'Regenerate RSA keys',
    usage: null,
    action: (args) async => getIt<RsagenCommand>().execute(args: args)))

    ..register((
    name: 'x',
    description: 'Patch executable with public RSA key',
    usage: './cpw x [executable] [--marker="..."]',
    action: (args) async => getIt<PatchCommand>().execute(args: args)))

    ..register((
    name: 'initial',
    description: "Create initial (base) revision, doesn't create lists",
    usage: null,
    action: (args) async => getIt<InitialCommand>().execute(args: args)))

    ..register((
    name: 'new',
    description: 'Create next revision, creates lists',
    usage: null,
    action: (args) async => getIt<NewCommand>().execute(args: args)))

    ..register((
    name: 'listgen',
    description: 'Full regeneration of files.md5',
    usage: './cpw listgen [--type=element]',
    action: (args) async => getIt<ListgenCommand>().execute(args: args)));

  return registry;
}