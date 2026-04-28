/// Base class for all database related errors.
/// It catches only database errors, without intercepting everything.
sealed class DatabaseException implements Exception {
  const DatabaseException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? '$message: $cause'
      : message;
}

/// Error connecting to the database (incorrect credentials, network, database not running).
final class DatabaseConnectionException extends DatabaseException {
  const DatabaseConnectionException(super.message, [super.cause]);
}

/// Request execution error (syntax, constraint violation, timeout).
final class DatabaseQueryException extends DatabaseException {
  const DatabaseQueryException(String message, {this.query, Object? cause})
      : super(message, cause);
  final String? query;
}

/// Error executing script.
final class DatabaseScriptException extends DatabaseException {
  const DatabaseScriptException(String message, {this.failedAtLine, Object? cause})
      : super(message, cause);
  final int? failedAtLine;
}