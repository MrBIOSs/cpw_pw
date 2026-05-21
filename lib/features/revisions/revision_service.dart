import 'dart:io';
import 'package:path/path.dart' as path;
import '../../config/config.dart';
import '../../core/crypto/utils/base64_path_encoder.dart';
import '../../core/database/database.dart';
import '../../core/logger/logger_service.dart';
import '../../core/utils/utilities.dart';
import 'models/revision_state.dart';
import 'packer_service.dart';

/// Patcher revision management service.
final class RevisionService {
  RevisionService({
    required PatcherConfig config,
    required PackerService packer,
    required DbService dbService,
  })  : _config = config, _packer = packer,
        _dbService = dbService;

  final PatcherConfig _config;
  final PackerService _packer;
  final DbService _dbService;

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

  /// Returns the current state of revisions (from DB).
  Future<RevisionState> getCurrentState() async {
    await _dbService.initialize();
    if (!_dbService.isConnected) {
      return _readStateFromFiles();
    }
    try {
      final result = await _dbService.execute(
        'SELECT type, MAX(revision) as max_rev FROM files GROUP BY type',
      );

      final rows = result.rows;
      int getRev(String type, int fallback) {
        return rows.where((r) => r['type'] == type)
            .map((r) => Utils.parseInt(r['max_rev']))
            .firstOrNull ?? fallback;
      }

      return (
      elementCurrentVer: getRev('element', 1),
      launcherCurrentVer: getRev('launcher', 1),
      patcherCurrentVer:  getRev('patcher', 1),
      );
    } on DatabaseQueryException catch (e) {
      log.fine('Failed to read revision state from DB, falling back to files: $e');
      return _readStateFromFiles();
    } finally {
      await _dbService.dispose();
    }
  }

  /// Packs files, writes to the database, increments the version.
  Future<RevisionState> createNext({bool force = false}) async {
    final current = await getCurrentState();
    final nextState = (
    elementCurrentVer: current.elementCurrentVer + 1,
    launcherCurrentVer: current.launcherCurrentVer + 1,
    patcherCurrentVer: current.patcherCurrentVer + 1,
    );

    log.info('Creating next revision: ${current.elementCurrentVer} to ${nextState.elementCurrentVer}');

    await _dbService.initialize();

    try {
      for (final type in ['element', 'launcher', 'patcher']) {
        await _packFiles(type, nextState);
      }
      await _writeVersionFiles(nextState);
    } finally {
      await _dbService.dispose();
    }
    await _writeVersionFiles(nextState);

    log.info('Next revision prepared: ${nextState.elementCurrentVer}'
        '/${nextState.launcherCurrentVer}/${nextState.patcherCurrentVer}');
    return nextState;
  }

  /// Synchronizes version files with the current state from the database.
  Future<void> syncVersionFilesToDb() async {
    final state = await getCurrentState();

    for (final entry in [
      ('element', state.elementCurrentVer),
      ('launcher', state.launcherCurrentVer),
      ('patcher', state.patcherCurrentVer),
    ]) {
      final (type, rev) = entry;
      final file = File(_getVersionFilePath(type));
      final currentContent = (file.existsSync()) ? (await file.readAsString()).trim() : null;

      if (currentContent != '$rev') {
        log.warning('Version file for $type was out of sync ($currentContent to $rev). Auto-correcting.');
        await file.writeAsString('$rev\n');
      }
    }
  }

  Future<RevisionState> _readStateFromFiles() async {
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

  /// Packs files from new/{type}/ to CPW/{type}/{type}/ and writes metadata to the database.
  Future<void> _packFiles(String type, RevisionState state) async {
    final sourceDir = _getInputDirectory(type);
    final targetDir = _getOutputDirectory(type);
    final nextRev = state.getCurrent(type) + 1;
    final source = Directory(sourceDir);

    if (!source.existsSync()) {
      log.fine('Source directory empty: $sourceDir');
      return;
    }

    await for (final entity in source.list(recursive: true)) {
      if (entity is File && _isIncluded(entity)) {
        final relative = _toRelativePath(entity.path, type);

        // base64(data/config.ini) to ZGF0YV9jb25maWcuaW5p
        final targetName = Base64PathEncoder.encode(relative);
        final targetPath = path.join(targetDir, targetName);

        // [4-byte LE size][deflate(data)]
        final packResult = await _packer.pack(entity, File(targetPath));
        final folder = path.dirname(relative);
        final fileName = path.basename(relative);

        await _dbService.execute(
          '''
        INSERT INTO files (added, size, revision, md5, type, folder, folder_base64, file, file_base64)
        VALUES (:added, :size, :revision, :md5, :type, :folder, :folderBase64, :file, :fileBase64)
        ON DUPLICATE KEY UPDATE 
          size = :size, 
          revision = :revision, 
          md5 = :md5
        ''',
          {
            'added': nextRev,
            'size': packResult.packedSize,
            'revision': nextRev,
            'md5': packResult.md5,
            'type': type,
            'folder': folder == '.' ? '' : folder,
            'folderBase64': Base64PathEncoder.encodeFolder(folder == '.' ? '' : folder),
            'file': fileName,
            'fileBase64': Base64PathEncoder.encodeFileName(fileName),
          },
        );

        log.fine('Packed & recorded: $relative to $targetName (rev $nextRev)');
      }
    }
  }

  /// excludes service files.
  bool _isIncluded(File file) {
    final name = path.basename(file.path).toLowerCase();
    return !['.svn', '_svn', 'version.sw', 'thumbs.db', '.ds_store']
        .contains(name) && !name.startsWith('.');
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
      _config.resolvePath('${_config.patchPath}/${_config.patchCpwDir}/$type/$type');

  /// Returns the path to the input directory for the type.
  String _getInputDirectory(String type) =>
      _config.resolvePath('${_config.patchPath}/${_config.patchNewDir}/$type');

  /// Returns the path to the version file for the type.
  /// Example: /app/files/CPW/element/version
  String _getVersionFilePath(String type) =>
      _config.resolvePath('${_config.patchPath}/${_config.patchCpwDir}/$type/version');

  /// Converts an absolute file path to a relative one.
  /// Example: /app/files/new/element/data/config.ini to data/config.ini
  String _toRelativePath(String fullPath, String type) {
    final sourceDir = _getInputDirectory(type);
    return path.relative(fullPath, from: sourceDir);
  }
}