import 'dart:async';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/core/utils/ansi_colors.dart';

/// A service for managing logging in a CLI application.
///
/// Provides simultaneous console output (with color support)
/// and writing to rotating log files.
final class LoggerService {

  /// Creates a service instance.
  ///
  /// [logDir] - path to the directory where log files will be stored.
  /// [minLevel] - minimum log level to process (default: INFO).
  LoggerService({
    required String logDir,
    Level minLevel = Level.INFO,
  })  : _logDir = logDir,
        _minLevel = minLevel;

  final String _logDir;
  final Level _minLevel;

  IOSink? _consoleSink;
  IOSink? _errorsSink;
  StreamSubscription<LogRecord>? _subscription;

  /// Creates directories, opens file write streams
  /// and subscribes to the system log bus [Logger.root].
  Future<void> initialize() async {
    await Directory(_logDir).create(recursive: true);

    _consoleSink = File(path.join(_logDir, 'console.log')).openWrite();
    _errorsSink = File(path.join(_logDir, 'errors.log')).openWrite();

    Logger.root.level = _minLevel;
    _subscription = Logger.root.onRecord.listen(_handleRecord);
  }

  /// Closes file streams and unsubscribes from logs.
  ///
  /// It is recommended to call it before the application is terminated.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _consoleSink?.flush();
    await _errorsSink?.flush();
    await _consoleSink?.close();
    await _errorsSink?.close();
  }

  /// Internal handler for each log entry.
  void _handleRecord(LogRecord record) {
    final time = record.time.toIso8601String().split('T')[1].split('.')[0];
    final levelStr = record.level.name;
    final prefix = '[$levelStr] %$time%';
    final location = '*${record.loggerName}*';
    final message = record.message;
    final errorPart = record.error != null ? ' | ${record.error}' : '';
    final stackPart = record.stackTrace != null ? '\n${record.stackTrace}' : '';

    final logLine = '$prefix $location - $message$errorPart';

    final color = _getColor(record.level);

    // Output to the system console
    if (record.level >= Level.WARNING) {
      stderr.writeln(color(logLine));
      if (stackPart.isNotEmpty) stderr.writeln(color(stackPart));
    } else {
      stdout.writeln(color(logLine));
    }

    // Writing to files
    _consoleSink?.write('$logLine$stackPart\n');
    if (record.level >= Level.SEVERE || record.error != null) {
      _errorsSink?.write('$logLine$stackPart\n');
    }
  }

  /// Selects the appropriate [AnsiPen] depending on the log importance level.
  AnsiPen _getColor(Level level) => switch (level) {
    Level.SEVERE => AnsiColors.error,
    Level.WARNING => AnsiColors.warning,
    Level.INFO => AnsiColors.description,
    Level.CONFIG => AnsiColors.command,
    Level.FINE => AnsiColors.dim,
    _ => AnsiColors.monochrome,
  };
}

extension LoggerExt on Object {
  Logger get log => Logger(runtimeType.toString());
}