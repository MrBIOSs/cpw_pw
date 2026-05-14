import 'dart:io';
import 'package:path/path.dart' as path;

import '../../config/config.dart';
import '../../core/database/database.dart';
import '../../core/logger/logger_service.dart';
import 'models/revision_state.dart';

/// Patcher revision management service.
final class RevisionService {
  RevisionService({
    required PatcherConfig config,
    DbService? dbService,
  })  : _config = config,
        _dbService = dbService;

  final PatcherConfig _config;
  final DbService? _dbService;

  RevisionState get getInitialState => _loadInitialStateFromConfig();

  /// Creates the initial (base) revision.
  /// Returns information about the created revision.
  Future<RevisionState> createInitial() async {
    log.info('Initializing base revision state...');

    final initialState = _loadInitialStateFromConfig();
    log.fine('Loaded initial state from config: $initialState');

    await _createInputStructure();
    log.fine('Input directory structure created');

    await _createOutputStructure(initialState);
    log.fine('Output directory structure created');

    await _writeVersionFiles(initialState);
    log.fine('Version files initialized');

    log.info('Base revision state initialized');
    return initialState;
  }

  /// Returns the current state of revisions (from version files).
  Future<RevisionState> getCurrentState() async {
    Future<int> readVersion(String type) async {
      final file = File(_getVersionFilePath(type));
      if (!file.existsSync()) return 1;
      final content = (await file.readAsString()).trim();
      return int.tryParse(content) ?? 1;
    }

    final element = await readVersion('element');
    final launcher = await readVersion('launcher');
    final patcher = await readVersion('patcher');

    return (
    elementCurrentVer: element,
    launcherCurrentVer: launcher,
    patcherCurrentVer: patcher,
    );
  }

  RevisionState _loadInitialStateFromConfig() {
    final element = _config.minElementVer;
    final launcher = _config.minLauncherVer;
    final patcher = _config.minPatcherVer;

    return (
    elementCurrentVer: element,
    launcherCurrentVer: launcher,
    patcherCurrentVer: patcher,
    );
  }

  /// Creates an input directory structure (new/{type}/).
  Future<void> _createInputStructure() async {
    for (final type in ['element', 'launcher', 'patcher']) {
      final inputDir = _getInputDirectory(type);
      final dir = Directory(inputDir);

      if (dir.existsSync()) {
        log.fine('Input directory already exists: $inputDir');
        continue;
      }

      await dir.create(recursive: true);
      log.fine('Created input directory: $inputDir');
    }
  }

  /// Creates an output directory structure for each type.
  Future<void> _createOutputStructure(RevisionState state) async {
    for (final type in ['element', 'launcher', 'patcher']) {
      final targetDir = _getOutputDirectory(type);
      final dir = Directory(targetDir);

      if (dir.existsSync()) {
        log.fine('Directory already exists: $targetDir');
        continue;
      }

      await dir.create(recursive: true);
      log.fine('Created: $targetDir');
    }
  }

  /// Initializes version files to the current revision value.
  Future<void> _writeVersionFiles(RevisionState state) async {
    for (final entry in [
      ('element', state.elementCurrentVer),
      ('launcher', state.launcherCurrentVer),
      ('patcher', state.patcherCurrentVer),
    ]) {
      final (type, version) = entry;
      final versionPath = _getVersionFilePath(type);
      final file = File(versionPath);

      await file.writeAsString('$version\n');
      log.fine('Written $version to $versionPath');
    }
  }

  /// Returns the path to the output directory for the type.
  /// Example: /app/files/CPW/element/element
  String _getOutputDirectory(String type) =>
      path.join(_config.baseDir, _config.patchPath, _config.patchCpwDir, type, type);

  /// Returns the path to the input directory for the type.
  String _getInputDirectory(String type) =>
      path.join(_config.baseDir, _config.patchPath, _config.patchNewDir, type);

  /// Returns the path to the version file for the type.
  /// Example: /app/files/CPW/element/version
  String _getVersionFilePath(String type) =>
      path.join(_config.baseDir, _config.patchPath, _config.patchCpwDir, type, 'version');
}