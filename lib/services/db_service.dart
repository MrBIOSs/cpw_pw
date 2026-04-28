import 'dart:io';
import '../config/patcher_config.dart';
import '../database/database.dart';
import 'logger_service.dart';

/// Initialization, migrations, script execution.
final class DbService {
  DbService({
    required PatcherConfig config,
    IDatabase? adapter,
  })  : _config = config,
        _db = adapter ?? MysqlAdapter(config);

  final PatcherConfig _config;
  final IDatabase _db;

  DbType get type => _db.type;

  /// Initializes a connection to the database.
  Future<void> initialize() async {
    log.info('Connecting to database at ${_config.dbHost}...');
    await _db.connect();
    log.info('Database connected');
  }

  /// Executes the initialization script, automatically selecting the version for the current database.
  Future<ScriptResult> runInstallScript({String? baseDir}) async {
    final dir = baseDir ?? 'config';
    final scriptPath = '$dir/install_${type.name}.sql';
    final scriptFile = File(scriptPath);

    if (!scriptFile.existsSync()) {
      throw FileSystemException('Install script not found', scriptFile.path);
    }

    final script = await scriptFile.readAsString();
    log.info('Running install script for ${type.name.toUpperCase()}: ${scriptFile.path}');

    final result = await _db.executeScript(
      script,
      onProgress: (done, total) {
        if (done % 10 == 0 || done == total) {
          log.info('Progress: $done/$total queries executed');
        }
      },
    );

    log.info(
      'Install script completed: '
          '${result.successfulQueries}/${result.totalQueries} queries successful',
    );

    return result;
  }

  /// Checks that the required tables exist.
  /// Returns a list of missing tables.
  Future<List<String>> checkRequiredTables(List<String> tables) async {
    final missing = <String>[];

    for (final table in tables) {
      try {
        final result = await _db.execute(
            'SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = :name',
            {'name': table}
        );

        if (result.rows.isEmpty) {
          missing.add(table);
        }
      } catch (e) {
        log.fine('Fallback check for table $table: $e');
        try {
          await _db.execute('SELECT 1 FROM `$table` LIMIT 0');
        } on DatabaseQueryException {
          missing.add(table);
        }
      }
    }


    return missing;
  }

  /// Closes the connection to the database.
  Future<void> dispose() async {
    if (_db.isConnected) {
      log.info('Closing database connection...');
      await _db.close();
      log.info('Database connection closed');
    }
  }
}