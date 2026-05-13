import '../../config/config.dart';
import '../../core/crypto/crypto.dart';
import '../../core/database/database.dart';
import '../../core/logger/logger_service.dart';
import '../security/security.dart';
import 'validators.dart';

/// Database, keys, validation.
final class SetupService {
  SetupService({
    required DbService dbService,
    required RsaService rsaService,
    required PatcherConfig config,
  })  : _dbService = dbService,
        _rsaService = rsaService,
        _config = config;

  final DbService _dbService;
  final RsaService _rsaService;
  final PatcherConfig _config;

  /// Returns [SetupResult] with execution details.
  Future<SetupResult> initialize({bool skipKeys = false, bool skipDb = false}) async {
    final result = SetupResult.started();
    final validator = SetupValidator(_config);
    final errors = await validator.validate();

    if (errors.isNotEmpty) {
      log.severe('Validation failed: ${errors.join('; ')}');
      return result.completed(success: false, errors: errors);
    }
    result.addStep('Environment validated');

    if (!skipDb) {
      try {
        await _dbService.initialize();
        result.addStep('Database connected');

        final requiredTables = ['files'];
        final missing = await _dbService.checkRequiredTables(requiredTables);

        if (missing.isEmpty) {
          log.info('Database schema is up to date');
          result.addStep('Database schema already exists');
        } else {
          log.info('Running install script (missing tables: ${missing.join(', ')})');
          await _dbService.runInstallScript();
          result.addStep('Database initialized (${requiredTables.length} tables)');
        }
      } on DatabaseConnectionException catch (e) {
        log.severe('Database connection failed', e);
        return result.completed(
            success: false,
            errors: ['Cannot connect to database: ${e.message}']
        );
      } on DatabaseScriptException catch (e) {
        log.severe('Install script failed at query #${e.failedAtLine}', e);
        return result.completed(
            success: false,
            errors: ['Database initialization failed: ${e.message}']
        );
      } finally {
        await _dbService.dispose();
      }
    } else {
      result.addStep('Database setup skipped (--skip-db)');
    }

    if (!skipKeys) {
      try {
        if (_rsaService.hasKeys()) {
          log.info('RSA keys already exist, skipping generation');
          result.addStep('RSA keys already exist');
        } else {
          await _rsaService.generateAndSave();
          result.addStep('RSA keys generated (2048-bit)');
        }
      } on KeyGenerationException catch (e) {
        log.severe('Key generation failed', e);
        return result.completed(
            success: false,
            errors: ['Failed to generate RSA keys: ${e.message}']
        );
      }
    } else {
      result.addStep('Key generation skipped (--skip-keys)');
    }
    return result.completed(success: true);
  }
}

/// Result of initialization.
/// Display progress and errors.
final class SetupResult {
  SetupResult._();

  factory SetupResult.started() => SetupResult._();

  final List<String> _steps = [];
  final List<String> _errors = [];
  bool _success = false;
  bool _completed = false;

  void addStep(String message) {
    if (_completed) throw StateError('Cannot add step to completed result');
    _steps.add(message);
  }

  SetupResult completed({required bool success, List<String> errors = const []}) {
    _success = success;
    _errors.addAll(errors);
    _completed = true;
    return this;
  }

  bool get isSuccess => _success;
  List<String> get steps => List.unmodifiable(_steps);
  List<String> get errors => List.unmodifiable(_errors);
  bool get isCompleted => _completed;
}