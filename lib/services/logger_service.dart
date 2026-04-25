import 'dart:async';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

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

  static LoggerService? _instance;

  /// Returns an initialized service instance.
  ///
  /// Throws a [StateError] if the [initialize] method has not yet been called.
  static LoggerService get instance => _instance ?? (throw StateError('LoggerService not initialized'));

  static final AnsiPen _penSevere = AnsiPen()..red(bold: true);
  static final AnsiPen _penWarning = AnsiPen()..yellow();
  static final AnsiPen _penInfo = AnsiPen()..cyan();
  static final AnsiPen _penConfig = AnsiPen()..green();
  static final AnsiPen _penFine = AnsiPen()..gray(level: 0.5);
  static final AnsiPen _penDefault = AnsiPen();

  IOSink? _consoleSink;
  IOSink? _errorsSink;
  StreamSubscription<LogRecord>? _subscription;

  /// Creates directories, opens file write streams
  /// and subscribes to the system log bus [Logger.root].
  Future<void> initialize() async {
    _instance = this;
    await Directory(_logDir).create(recursive: true);

    _consoleSink = File(path.join(_logDir, 'console.log')).openWrite();
    _errorsSink = File(path.join(_logDir, 'errors.log')).openWrite();

    Logger.root.level = _minLevel;
    _subscription = Logger.root.onRecord.listen(_handleRecord);

    _setupSignalHandlers();
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
    Level.SEVERE => _penSevere,
    Level.WARNING => _penWarning,
    Level.INFO => _penInfo,
    Level.CONFIG => _penConfig,
    Level.FINE => _penFine,
    _ => _penDefault,
  };

  /// Intercepts system signals to ensure files are closed correctly.
  void _setupSignalHandlers() {
    ProcessSignal.sigint.watch().listen((_) => _flushAndExit());

    if (Platform.isWindows == false) {
      ProcessSignal.sigterm.watch().listen((_) => _flushAndExit());
    }
  }

  /// Clears buffers before exiting.
  Future<void> _flushAndExit() async {
    await dispose();
    exit(0);
  }
}

extension LoggerExt on Object {
  Logger get log => Logger(runtimeType.toString());
}