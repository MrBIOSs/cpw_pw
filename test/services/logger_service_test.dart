import 'dart:io';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:cpw_pw/core/logger/logger_service.dart';

void main() {
  late Directory tempDir;
  late LoggerService loggerService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('logger_service_test_');
  });

  tearDown(() async {
    Logger.root.clearListeners();
    Logger.root.level = Level.ALL;

    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('LoggerService Tests', () {
    test('initialize() should create log directory and files', () async {
      loggerService = LoggerService(logDir: tempDir.path);

      expect(File(p.join(tempDir.path, 'console.log')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'errors.log')).existsSync(), isFalse);

      await loggerService.initialize();

      expect(Directory(tempDir.path).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'console.log')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'errors.log')).existsSync(), isTrue);
      expect(Logger.root.level, equals(Level.INFO));

      await loggerService.dispose();
    });

    test('Log records should be written to console.log', () async {
      loggerService = LoggerService(logDir: tempDir.path);
      await loggerService.initialize();

      const testMessage = 'Test info message';
      Logger('TestLogger').info(testMessage);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await loggerService.dispose();

      final consoleLog = File(p.join(tempDir.path, 'console.log')).readAsStringSync();
      final errorsLog = File(p.join(tempDir.path, 'errors.log')).readAsStringSync();

      expect(consoleLog, contains('INFO'));
      expect(consoleLog, contains('TestLogger'));
      expect(consoleLog, contains(testMessage));
      expect(errorsLog.trim(), isEmpty);
    });

    test('Severe logs and errors should be written to errors.log', () async {
      loggerService = LoggerService(logDir: tempDir.path);
      await loggerService.initialize();

      const errorMessage = 'Critical failure';
      Logger('ErrorLogger').severe(errorMessage);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await loggerService.dispose();

      final consoleLog = File(p.join(tempDir.path, 'console.log')).readAsStringSync();
      final errorsLog = File(p.join(tempDir.path, 'errors.log')).readAsStringSync();

      expect(consoleLog, contains(errorMessage));
      expect(errorsLog, contains('SEVERE'));
      expect(errorsLog, contains(errorMessage));
    });

    test('Logs below minLevel should be ignored', () async {
      loggerService = LoggerService(logDir: tempDir.path, minLevel: Level.WARNING);
      await loggerService.initialize();

      Logger('TestLogger').info('This should not be logged');
      Logger('TestLogger').warning('This warning message must be captured');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await loggerService.dispose();

      final consoleLog = File(p.join(tempDir.path, 'console.log')).readAsStringSync();
      expect(consoleLog, contains('[WARNING]'));
      expect(consoleLog, isNot(contains('[INFO]')));
    });

    test('The LoggerExt extension correctly creates a named logger based on the runtimeType', () {
      final testObject = DummyClass();
      final logger = testObject.log;

      expect(logger.name, equals('DummyClass'));
    });
  });
}

class DummyClass {}
