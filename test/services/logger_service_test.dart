import 'dart:io';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:ansicolor/ansicolor.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';

void main() {
  final testLogDir = p.join(Directory.systemTemp.path, 'logger_test_logs');

  setUp(() {
    ansiColorDisabled = true;
  });

  tearDown(() async {
    final dir = Directory(testLogDir);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  group('LoggerService Tests', () {
    test('Initialization should set the singleton instance', () async {
      final logger = LoggerService(logDir: testLogDir);
      await logger.initialize();

      expect(LoggerService.instance, equals(logger));

      await logger.dispose();
    });

    test('initialize() should create log directory and files', () async {
      final logger = LoggerService(logDir: testLogDir);
      await logger.initialize();

      expect(Directory(testLogDir).existsSync(), isTrue);
      expect(File(p.join(testLogDir, 'console.log')).existsSync(), isTrue);
      expect(File(p.join(testLogDir, 'errors.log')).existsSync(), isTrue);

      await logger.dispose();
    });

    test('Log records should be written to console.log', () async {
      final logger = LoggerService(logDir: testLogDir);
      await logger.initialize();

      final testMessage = 'Test info message';
      Logger('TestLogger').info(testMessage);

      await Future<void>.delayed(Duration(milliseconds: 100));
      await logger.dispose();

      final consoleLog = await File(p.join(testLogDir, 'console.log')).readAsString();
      expect(consoleLog, contains('INFO'));
      expect(consoleLog, contains('TestLogger'));
      expect(consoleLog, contains(testMessage));
    });

    test('Severe logs and errors should be written to errors.log', () async {
      final logger = LoggerService(logDir: testLogDir);
      await logger.initialize();

      final errorMessage = 'Critical failure';
      Logger('ErrorLogger').severe(errorMessage);

      await Future<void>.delayed(Duration(milliseconds: 100));
      await logger.dispose();

      final errorLog = await File(p.join(testLogDir, 'errors.log')).readAsString();
      expect(errorLog, contains('SEVERE'));
      expect(errorLog, contains(errorMessage));
    });

    test('Logs below minLevel should be ignored', () async {
      final logger = LoggerService(logDir: testLogDir, minLevel: Level.WARNING);
      await logger.initialize();

      Logger('TestLogger').info('This should not be logged');

      await Future<void>.delayed(Duration(milliseconds: 100));
      await logger.dispose();

      final consoleLog = await File(p.join(testLogDir, 'console.log')).readAsString();
      expect(consoleLog, isEmpty);
    });
  });
}
