import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import '../app/command_registry.dart';
import '../config/config.dart';
import '../core/database/database.dart';
import '../core/logger/logger_service.dart';
import '../features/revisions/revisions.dart';
import '../features/security/security.dart';
import '../features/setup/setup.dart';

/// Global service locator.
final getIt = GetIt.instance;

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

  getIt.registerLazySingleton<IDatabase>(() => MysqlAdapter(config));
  getIt.registerLazySingleton<DbService>(() => DbService(
      config: config,
      adapter: getIt<IDatabase>()
  ));
}

void _registerCrypto() {
  final baseDir = getIt<PatcherConfig>().baseDir;

  getIt.registerLazySingleton<IKeyStorage>(() => FileKeyStorage(baseDir: baseDir));
  getIt.registerLazySingleton<RsaService>(() => RsaService(storage: getIt<IKeyStorage>()));
}

void _registerFeatures() {
  getIt.registerLazySingleton<SetupService>(() => SetupService(
    dbService: getIt<DbService>(),
    rsaService: getIt<RsaService>(),
    config: getIt<PatcherConfig>()
  ));

  getIt.registerLazySingleton<RevisionService>(() => RevisionService(
      config: getIt<PatcherConfig>(),
      dbService: getIt.isRegistered<DbService>() ? getIt<DbService>() : null,
  ));

  getIt.registerLazySingleton<ManifestService>(() => ManifestService(
      config: getIt<PatcherConfig>(),
      dbService: getIt<DbService>(),
      rsaService: getIt<RsaService>()
  ));
}

void _registerCommands() {
  getIt.registerFactory<InstallCommand>(InstallCommand.new);
  getIt.registerFactory<RsagenCommand>(RsagenCommand.new);
  getIt.registerFactory<InitialCommand>(InitialCommand.new);

  getIt.registerFactory<ListgenCommand>(ListgenCommand.new);

  getIt.registerSingleton<CommandRegistry>(_buildCommandRegistry());
}

/// Registers all available commands.
CommandRegistry _buildCommandRegistry() {
  final registry = CommandRegistry();

  registry.register((
  name: 'install',
  description: 'Install updater: database setup, RSA keys generation, paths',
  usage: null,
  action: (args) async => getIt<InstallCommand>().execute(args: args)));

  registry.register((
  name: 'rsagen',
  description: 'Regenerate RSA keys',
  usage: null,
  action: (args) async => getIt<RsagenCommand>().execute(args: args)));

  registry.register((
  name: 'x',
  description: 'Patch executable with public RSA key',
  usage: './cpw x [executable]',
  action: (args) async => 0,
  ));

  registry.register((
  name: 'initial',
  description: 'Create initial (base) revision, doesn\'t create lists',
  usage: null,
  action: (args) async => getIt<InitialCommand>().execute(args: args)));

  registry.register((
  name: 'new',
  description: 'Create next revision, creates lists',
  usage: './cpw new',
  action: (args) async => 0,
  ));

  registry.register((
  name: 'listgen',
  description: 'Full regeneration of files.md5',
  usage: './cpw listgen [--type=element]',
  action: (args) async => getIt<ListgenCommand>().execute(args: args)));

  return registry;
}