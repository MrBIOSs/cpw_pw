import 'dart:io';
import '../../../config/config.dart';
import '../../../features/security/security.dart';
import '../../core/database/database.dart';
import '../../core/logger/logger_service.dart';
import 'models/revision_state.dart';

/// Service for generating manifests (files.md5), incremental patches (v-N.inc) and RSA signatures.
final class ManifestService {
  ManifestService({
    required PatcherConfig config,
    required DbService dbService,
    required RsaService rsaService,
  }) : _config = config, _db = dbService, _rsa = rsaService;

  final PatcherConfig _config;
  final DbService _db;
  final RsaService _rsa;

  /// Generates all artifacts for the specified content type.
  /// Called by "new" (automatically) and "listgen" (manually for restoration).
  Future<void> generateManifests(String type, RevisionState state) async {
    final currentRev = state.getCurrent(type);
    final minRev = _config.getMinRevForType(type);

    if (currentRev < minRev) {
      throw StateError('Current revision ($currentRev) is less than minimum ($minRev). Run `./cpw initial` first.');
    }
    log.info('Generating manifests for $type (rev $minRev : $currentRev)...');

    final result = await _db.execute(
      'SELECT md5, folder_base64, file_base64, revision, added, size FROM files WHERE type = :type ORDER BY revision, folder_base64, file_base64',
      {'type': type},
    );
    final files = result.rows;

    if (files.isEmpty) {
      log.warning('No files found in DB for type=$type. Skipping manifest generation.');
      return;
    }

    await _writeFilesMd5(type, files, currentRev);
    log.fine('files.md5 written');

    await _rsa.signFile(_getManifestPath(type));
    log.fine('RSA signature appended');

    await _generateIncrementalPatches(type, files, minRev, currentRev);
    log.fine('Incremental patches generated');

    await File(_getVersionPath(type)).writeAsString('$currentRev\n');
    log.info('$type manifests completed successfully');
  }

  Future<void> _writeFilesMd5(String type, List<Map<String, dynamic>> files, int currentRev) async {
    final sink = File(_getManifestPath(type)).openWrite();

    sink.write('# $currentRev\n');

    String lastFolder = '';
    for (final f in files) {
      final folder = f['folder_base64'] as String;
      final file = f['file_base64'] as String;
      final md5 = f['md5'] as String;

      if (folder != lastFolder) {
        lastFolder = folder;
        sink.write('$md5 $folder$file\n');
      } else {
        sink.write('$md5 $file\n');
      }
    }

    await sink.flush();
    await sink.close();
  }

  /// Generates v-N.inc files for each revision range.
  Future<void> _generateIncrementalPatches(
      String type,
      List<Map<String, dynamic>> files,
      int minRev,
      int currentRev,
      ) async {
    await _cleanupOldPatches(type, minRev, currentRev);

    for (int fromRev = minRev; fromRev < currentRev; fromRev++) {
      final diff = currentRev - fromRev;
      final patchPath = _getPatchPath(type, diff);
      final sink = File(patchPath).openWrite();

      final totalSize = _config.addSize
          ? ' ${_calculateTotalSize(files, fromRev, currentRev)}'
          : '';
      sink.write('# $fromRev $currentRev$totalSize\n');

      String lastFolder = '';
      for (final f in files) {
        final revision = f['revision'] as int;
        final added = f['added'] as int;
        final folder = f['folder_base64'] as String;
        final file = f['file_base64'] as String;
        final md5 = f['md5'] as String;

        if (revision > fromRev && revision <= currentRev) {
          // '+' = new file in this patch, '!' = changed
          final prefix = (added == revision) ? '+' : '!';

          if (folder != lastFolder) {
            lastFolder = folder;
            sink.write('$prefix$md5 $folder$file\n');
          } else {
            sink.write('$prefix$md5 $file\n');
          }
        }
      }

      await sink.flush();
      await sink.close();
      await _rsa.signFile(patchPath);
    }
  }

  /// Removes old .inc files.
  Future<void> _cleanupOldPatches(String type, int minRev, int currentRev) async {
    final dir = Directory(_getOutputDir(type));
    if (!dir.existsSync()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.inc')) {
        final name = entity.path.split('/').last;
        final match = RegExp(r'v-(\d+)\.inc').firstMatch(name);

        if (match != null) {
          final diff = int.parse(match.group(1)!);
          final impliedFrom = currentRev - diff;

          if (impliedFrom < minRev || impliedFrom >= currentRev) {
            await entity.delete();
          }
        }
      }
    }
  }

  int _calculateTotalSize(List<Map<String, dynamic>> files, int from, int to) {
    return files.where((f) {
      final rev = f['revision'] as int;
      return rev > from && rev <= to;
    }).fold<int>(0, (sum, f) => sum + (f['size'] as int));
  }

  /// Directory for manifests and patches.
  /// Example: /app/files/CPW/element
  String _getOutputDir(String type) =>
      _config.resolvePath('${_config.patchPath}/${_config.patchCpwDir}/$type');

  /// Path to incremental patch.
  /// Example: /app/files/CPW/element/v-3.inc
  String _getPatchPath(String type, int diff) =>
      _config.resolvePath('${_getOutputDir(type)}/v-$diff.inc');

  /// Example: /app/files/CPW/element/files.md5
  String _getManifestPath(String type) =>
      _config.resolvePath('${_getOutputDir(type)}/files.md5');

  /// Example: /app/files/CPW/element/version
  String _getVersionPath(String type) =>
      _config.resolvePath('${_getOutputDir(type)}/version');
}