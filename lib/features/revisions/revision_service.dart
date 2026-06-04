import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/core/crypto/utils/base64_path_encoder.dart';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';
import 'package:cpw_pw/core/utils/utilities.dart';
import 'package:cpw_pw/features/revisions/models/revision_state.dart';
import 'package:cpw_pw/features/revisions/packer_service.dart';

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

  RevisionState get getInitialState => _config.getMinRevisionState();

  /// Creates the initial (base) revision.
  /// Returns information about the created revision.
  Future<RevisionState> createInitial() async {
    log.info('Initializing base revision state...');

    final initialState = _config.getMinRevisionState();
    log.fine('Loaded initial state from config: $initialState');

    await _createInputStructure();
    log.fine('Input directory structure created');

    await _createOutputStructure(initialState);
    log.fine('Output directory structure created');

    try {
      log.info('Preparing database for initial state...');

      if (!_dbService.isConnected) {
        await _dbService.initialize();
      }
      log.info('Clearing "files" table...');

      await _dbService.execute('TRUNCATE TABLE `files`');

      log.info('Table "files" cleared successfully');
    } catch (e) {
      log.severe('Failed to clear "files" table during initialization: $e');
    } finally {
      await _dbService.dispose();
    }

    await _writeVersionFiles(initialState, initialState);
    log
      ..fine('Version files initialized')
      ..info('Base revision state initialized');
    return initialState;
  }

  /// Packs files, writes to the database, increments the version.
  Future<RevisionState> createNext({bool force = false}) async {
    final current = await syncVersionFilesToDb();

    final hasNewElement = !force && await _hasFilesToPack('element');
    final hasNewLauncher = !force && await _hasFilesToPack('launcher');
    final hasNewPatcher = !force && await _hasFilesToPack('patcher');

    final nextState = (
    elementCurrentVer: hasNewElement ? current.elementCurrentVer + 1 : current.elementCurrentVer,
    launcherCurrentVer: hasNewLauncher ? current.launcherCurrentVer + 1 : current.launcherCurrentVer,
    patcherCurrentVer: hasNewPatcher ? current.patcherCurrentVer + 1 : current.patcherCurrentVer,
    );

    log
      ..info('Current state: ${current.elementCurrentVer}/${current.launcherCurrentVer}/${current.patcherCurrentVer}')
      ..info('Next state: ${nextState.elementCurrentVer}/${nextState.launcherCurrentVer}/${nextState.patcherCurrentVer}');

    try {
      if (!_dbService.isConnected) {
        await _dbService.initialize();
      }
      for (final type in ['element', 'launcher', 'patcher']) {
        final currentVer = current.getCurrent(type);
        final nextVer = nextState.getCurrent(type);

        if (nextVer == currentVer && !force) {
          log.info('No new files detected for $type. Version remains $currentVer. Skipping.');
          continue;
        }

        await _packFiles(type, nextState, force: force);
      }
      await _writeVersionFiles(current, nextState);
    } finally {
      await _dbService.dispose();
    }

    log.info('Next revision prepared: ${nextState.elementCurrentVer}'
        '/${nextState.launcherCurrentVer}/${nextState.patcherCurrentVer}');
    return nextState;
  }

  /// Synchronizes version files with the current state from the database.
  Future<RevisionState> syncVersionFilesToDb() async {
    final state = await _getCurrentState();

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
    return state;
  }

  /// Checks if there are files in the folder "new/{type}/"
  Future<bool> _hasFilesToPack(String type) async {
    final sourcePath = _config.resolveSubDir(_config.patchNewDir, type);
    final sourceDir = Directory(sourcePath);

    if (!sourceDir.existsSync()) return false;

    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is File && _isIncluded(entity)) {
        return true;
      }
    }
    return false;
  }

  /// Returns the current state of revisions (from DB).
  Future<RevisionState> _getCurrentState() async {
    try {
      if (!_dbService.isConnected) {
        await _dbService.initialize();
      }

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
  Future<void> _packFiles(String type, RevisionState state, {bool force = false}) async {
    final sourcePath = _config.resolveSubDir(_config.patchNewDir, type);
    final targetPath = _getOutputDirectory(type);
    final nextRev = state.getCurrent(type);
    final sourceDir = Directory(sourcePath);

    if (!sourceDir.existsSync()) {
      log.fine('Source directory empty: $sourcePath');
      return;
    }

    if (force) {
      await _dbService.execute(
        'DELETE FROM files WHERE type = :type AND revision = :revision',
        {'type': type, 'revision': nextRev},
      );
    }

    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is File && _isIncluded(entity)) {
        final relative = _toRelativePath(entity.path, type);

        // base64(data/config.ini) to ZGF0YV9jb25maWcuaW5p
        final targetName = Base64PathEncoder.encode(relative);
        final targetPathFile = path.join(targetPath, targetName);

        // [4-byte LE size][deflate(data)]
        final packResult = await _packer.pack(entity, File(targetPathFile));
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
            'folderBase64': Base64PathEncoder.encode(folder == '.' ? '' : folder),
            'file': fileName,
            'fileBase64': Base64PathEncoder.encode(fileName),
          },
        );

        log.fine('Packed & recorded: $relative to $targetName (rev $nextRev)');
      }
    }

    await _cleanupSourceDirectory(
      sourceDir,
      removeFiles: _config.removeFiles,
    );
  }

  /// excludes service files.
  bool _isIncluded(File file) {
    final name = path.basename(file.path).toLowerCase();
    return !['.svn', '_svn', 'version.sw', 'thumbs.db', '.ds_store']
        .contains(name) && !name.startsWith('.');
  }

  /// Creates an input directory structure (new/{type}/).
  Future<void> _createInputStructure() async {
    for (final type in ['element', 'launcher', 'patcher']) {
      final inputDir = _config.resolveSubDir(_config.patchNewDir, type);
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
      final baseTypeDir = Directory(_config.resolveSubDir(_config.patchCpwDir, type));

      if (baseTypeDir.existsSync()) {
        log.info('Output directory and its subfolders exist, performing deep cleanup: ${baseTypeDir.path}');
        try {
          await baseTypeDir.delete(recursive: true);
          log.fine('Fully removed old directory: ${baseTypeDir.path}');
        } catch (e) {
          log.severe('Failed to perform deep cleanup on ${baseTypeDir.path}: $e');
        }
      }

      await dir.create(recursive: true);
      log.fine('Created: $targetDir');
    }

    try {
      final infoDir = Directory(_config.resolveSubDir(_config.patchCpwDir, 'info'));

      if (!infoDir.existsSync()) {
        await infoDir.create(recursive: true);
        log.fine('Created info directory: ${infoDir.path}');
      }

      final pidFile = File('${infoDir.path}/pid');
      await pidFile.writeAsString('101');
      log.fine('Created pid file with value 101');
    } catch (e) {
      log.severe('Failed to create info/pid structure: $e');
    }
  }

  /// Initializes version files to the current revision value.
  Future<void> _writeVersionFiles(RevisionState oldState, RevisionState newState) async {
    final entries = [
      ('element', oldState.elementCurrentVer, newState.elementCurrentVer),
      ('launcher', oldState.launcherCurrentVer, newState.launcherCurrentVer),
      ('patcher', oldState.patcherCurrentVer, newState.patcherCurrentVer),
    ];

    for (final (type, oldVer, newVer) in entries) {
      final versionPath = _getVersionFilePath(type);
      final file = File(versionPath);

      if (oldVer == newVer && file.existsSync()) {
        log.fine('Version for $type has not changed ($oldVer). Skipping file write.');
        continue;
      }

      await file.writeAsString('$newVer\n');
      log.fine('Written updated version $newVer to $versionPath');
    }
  }

  /// Cleans up the source directory after packing.
  /// If removeFiles=true - removes files, then removes all empty folders.
  Future<void> _cleanupSourceDirectory(
      Directory sourceDir, {
        required bool removeFiles,
      }) async {
    if (!removeFiles) return;

    log.fine('Cleaning up source directory: ${sourceDir.path}');
    final rootPath = sourceDir.path;

    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is File) {
        try { await entity.delete(); } catch (_) {}
      }
    }

    final dirs = <Directory>[];
    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is Directory && entity.path != rootPath) {
        dirs.add(entity);
      }
    }
    dirs.sort((a, b) => path.split(b.path).length.compareTo(path.split(a.path).length));

    for (final dir in dirs) {
      try {
        await dir.delete();
      } catch (_) {}
    }

    log.fine('Source cleanup completed');
  }

  /// Returns the path to the output directory for the type.
  /// Example: /app/files/CPW/element/element
  String _getOutputDirectory(String type) =>
      _config.resolveSubDir(_config.patchCpwDir, path.join(type, type));

  /// Returns the path to the version file for the type.
  /// Example: /app/files/CPW/element/version
  String _getVersionFilePath(String type) {
    final parentDir = _config.resolveSubDir(_config.patchCpwDir, type);
    return path.join(parentDir, 'version');
  }

  /// Converts an absolute file path to a relative one.
  /// Example: /app/files/new/element/data/config.ini to data/config.ini
  String _toRelativePath(String fullPath, String type) {
    final sourceDir = _config.resolveSubDir(_config.patchNewDir, type);
    return path.relative(fullPath, from: sourceDir);
  }
}