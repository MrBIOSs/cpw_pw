import 'dart:async';
import 'dart:io';

import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import '../../../config/config.dart';
import '../database.dart';

final class MysqlAdapter implements IDatabase {
  MysqlAdapter(this._config);

  final PatcherConfig _config;
  MySQLConnection? _connection;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected && _connection != null;

  @override
  DbType get type => DbType.mysql;

  @override
  Future<void> connect() async {
    if (isConnected) return;

    try {
      _connection = await MySQLConnection.createConnection(
        host: _config.dbHost,
        port: 3306,
        userName: _config.dbUser,
        password: _config.dbPassword,
        databaseName: _config.dbName,
        secure: false,
      );

      await _connection?.connect();
      _isConnected = true;
    } on MySQLException catch (e) {
      throw DatabaseConnectionException('MySQL Connection failed: ${e.message}', e);
    } on SocketException catch (e) {
      throw DatabaseConnectionException('Network error: ${e.message}', e);
    } catch (e) {
      throw DatabaseConnectionException('Unknown connection error: $e', e);
    }
  }

  @override
  Future<void> close() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
      _isConnected = false;
    }
  }

  @override
  Future<QueryResult> execute(String query, [Map<String, dynamic>? params]) async {
    _ensureConnected();

    try {
      final results = await _connection!.execute(query, params);
      final affectedRows = results.affectedRows.toInt();

      final rows = results.rows
          .map((row) => row.assoc())
          .toList(growable: false);
      return (affectedRows: affectedRows, rows: rows);
    } on MySQLException catch (e, st) {
      throw DatabaseQueryException(
        'Query failed: ${e.message}',
        query: query,
        cause: st,
      );
    }
  }

  @override
  Future<ScriptResult> executeScript(
      String script, {
        void Function(int executed, int total)? onProgress,
      }) async {
    _ensureConnected();

    final queries = _splitScript(script);
    final results = <QueryResult>[];
    var successCount = 0;

    for (var i = 0; i < queries.length; i++) {
      final query = queries[i].trim();
      if (query.isEmpty) continue;

      try {
        final result = await execute(query);
        results.add(result);
        successCount++;
        onProgress?.call(successCount, queries.length);
      } catch (e) {
        throw DatabaseScriptException(
          'Failed at query #${i + 1}: ${e.toString()}',
          failedAtLine: i + 1,
          cause: e,
        );
      }
    }

    return (
    totalQueries: queries.length,
    successfulQueries: successCount,
    results: results,
    );
  }

  @override
  Future<T> runTransaction<T>(Future<T> Function(dynamic ctx) callback) async {
    _ensureConnected();

    try {
      return await _connection!.transactional((ctx) async {
        return await callback(ctx);
      });
    } on MySQLException catch (e) {
      throw DatabaseQueryException(
        'Transaction failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// Splits by ';', removes comments.
  /// For complex scripts (strings with ';', stored procedures), a full-fledged SQL parser is required.
  List<String> _splitScript(String script) {
    final queries = <String>[];
    final lines = script.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('--') || trimmed.startsWith('#') || trimmed.startsWith('/*')) {
        continue;
      }
      buffer.writeln(line);

      if (trimmed.endsWith(';')) {
        final query = buffer.toString().trim();
        if (query.isNotEmpty && query != ';') {
          queries.add(query);
        }
        buffer.clear();
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      queries.add(remaining);
    }

    return queries;
  }

  void _ensureConnected() {
    if (!isConnected) throw StateError('Not connected to database');
  }
}