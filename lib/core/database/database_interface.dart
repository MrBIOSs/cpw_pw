import 'dart:async';
import 'package:cpw_pw/core/database/exceptions.dart';

enum DbType { mysql, postgres }

/// Abstraction for working with a relational DBMS.
abstract interface class IDatabase {
  /// Checks if the connection is established.
  bool get isConnected;
  DbType get type;

  /// Establishes a connection to the database.
  /// Throws [DatabaseConnectionException] on failure.
  Future<void> connect();

  /// Closes the connection and frees resources.
  Future<void> close();

  /// Executes one query (SELECT, INSERT, UPDATE, DELETE).
  /// Returns the number of affected rows or the result of the selection.
  Future<QueryResult> execute(String query, [Map<String, dynamic>? params]);

  /// Executes an SQL script (multiple queries separated by ';').
  /// [onProgress] is an optional callback for tracking progress.
  Future<ScriptResult> executeScript(
      String script, {
        void Function(int executed, int total)? onProgress,
      });

  /// All requests inside [callback] are either executed,
  /// or rolled back on error.
  Future<T> runTransaction<T>(Future<T> Function(dynamic ctx) callback);
}

/// The result of the request.
typedef QueryResult = ({
int affectedRows,
List<Map<String, dynamic>> rows,
});

/// Result of script execution.
typedef ScriptResult = ({
int totalQueries,
int successfulQueries,
List<QueryResult> results,
});