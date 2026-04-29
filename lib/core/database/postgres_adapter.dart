import 'dart:async';
import 'database_interface.dart';

/// Stub for the PostgreSQL adapter.
/// Implementation will be added during the migration to PostgreSQL.
/// Currently throws [UnimplementedError] when attempting to use.
final class PostgresAdapter implements IDatabase {
  PostgresAdapter({required String connectionString})
      : _connectionString = connectionString;

  final String _connectionString;
  // pg.Connection? _connection;

  @override
  bool get isConnected => false; // TODO: реализовать

  @override
  DbType get type => DbType.postgres;

  @override
  Future<void> connect() {
    throw UnimplementedError(
      'PostgreSQL support is not yet implemented. '
          'Use MysqlAdapter for now.',
    );
  }

  @override
  Future<void> close() async {
    // TODO: реализовать закрытие подключения
  }

  @override
  Future<QueryResult> execute(String query, [Map<String, dynamic>? params]) {
    throw UnimplementedError('PostgreSQL adapter is not ready');
  }

  @override
  Future<ScriptResult> executeScript(
      String script, {
        void Function(int executed, int total)? onProgress,
      }) {
    throw UnimplementedError('PostgreSQL adapter is not ready');
  }

  @override
  Future<T> runTransaction<T>(Future<T> Function(dynamic ctx) callback) {
    throw UnimplementedError('PostgreSQL adapter is not ready');
  }
}