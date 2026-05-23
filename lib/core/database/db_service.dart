import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';
import 'package:cpw_pw/core/database/database.dart';

/// Initialization, migrations, script execution.
class DbService {
  DbService({
    required PatcherConfig config,
    IDatabase? adapter,
  })  : _config = config,
        _db = adapter ?? MysqlAdapter(config);

  final PatcherConfig _config;
  final IDatabase _db;

  /// Current DBMS type
  DbType get type => _db.type;

  /// Checks if the connection is established.
  bool get isConnected => _db.isConnected;

  /// Initializes a connection to the database.
  Future<void> initialize() async {
    log.info('Connecting to database at ${_config.dbHost}...');
    await _db.connect();
    log.info('Database connected');
  }

  /// Executes the initialization script, automatically selecting the version for the current database.
  Future<ScriptResult> runInstallScript({String? customPath}) async {
    final scriptPath = customPath ??
        _config.resolvePath(path.join('config', 'install_${type.name}.sql'));
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

  /// Executes an arbitrary query.
  Future<QueryResult> execute(String query, [Map<String, dynamic>? params]) {
    return _db.execute(query, params);
  }

  Future<T> runTransaction<T>(Future<T> Function(dynamic) callback) {
    return _db.runTransaction(callback);
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