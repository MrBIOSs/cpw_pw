import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:cpw_pw/config/config.dart';
import 'package:cpw_pw/features/security/security.dart';
import 'package:cpw_pw/core/database/database.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';
import 'package:cpw_pw/core/utils/utilities.dart';
import 'package:cpw_pw/features/revisions/models/revision_state.dart';

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
  /// [isInitial] - if true, creates an empty baseline files.md5 for rev 1 with a signature.
  Future<void> generateManifests(String type, RevisionState state, {bool isInitial = false}) async {
    final minRev = _config.getMinRevisionState().getCurrent(type);
    final currentRev = isInitial ? minRev : state.getCurrent(type);

    if (currentRev < minRev) {
      throw StateError('Current revision ($currentRev) is less than minimum ($minRev). Run `./cpw initial` first.');
    }

    if (isInitial) {
      log.info('Generating initial empty baseline manifest for $type (rev $currentRev)...');

      final sink = File(_getManifestPath(type)).openWrite()
        ..write('# $currentRev\n');
      await sink.flush();
      await sink.close();
      log.fine('Empty baseline files.md5 written');

      await _rsa.signFile(_getManifestPath(type));
      log.fine('RSA signature appended to baseline manifest');

      await File(_getVersionPath(type)).writeAsString('$currentRev');
      log.info('$type initial manifest completed successfully');
      return;
    }

    log.info('Generating manifests for $type (rev $minRev to $currentRev)...');

    await _db.initialize();

    final result = await _db.execute(
      'SELECT md5, folder_base64, file_base64, revision, added, size FROM files WHERE type = :type ORDER BY revision, folder_base64, file_base64',
      {'type': type},
    );
    final files = result.rows;

    await _db.dispose();

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

    await File(_getVersionPath(type)).writeAsString('$currentRev');
    log.info('$type manifests completed successfully');
  }

  Future<void> _writeFilesMd5(String type, List<Map<String, dynamic>> files, int currentRev) async {
    final sink = File(_getManifestPath(type)).openWrite(encoding: latin1)
      ..write('# $currentRev');

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final folderBase64 = file['folder_base64'] as String;
      final fileBase64 = file['file_base64'] as String;
      final md5 = file['md5'] as String;

      sink.write('\n');

      if (folderBase64.isNotEmpty) {
        sink.write('$md5 $folderBase64/$fileBase64');
      } else {
        sink.write('$md5 $file');
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

    for (var fromRev = minRev; fromRev < currentRev; fromRev++) {
      final patchPath = _getPatchPath(type, fromRev);
      final sink = File(patchPath).openWrite();

      final totalSize = _config.addSize
          ? ' ${_calculateTotalSize(files, fromRev, currentRev)}'
          : '';
      sink.write('# $fromRev $currentRev$totalSize');

      for (final file in files) {
        final revision = Utils.parseInt(file['revision']);
        final added = Utils.parseInt(file['added']);
        final folderBase64 = file['folder_base64'] as String;
        final fileBase64 = file['file_base64'] as String;
        final md5 = file['md5'] as String;

        if (revision > fromRev && revision <= currentRev) {
          // '+' = new file in this patch, '!' = changed
          final prefix = (added == revision) ? '+' : '!';

          sink.write('\n');

          if (folderBase64.isNotEmpty) {
            sink.write('$prefix$md5 $folderBase64/$fileBase64');
          } else {
            sink.write('$prefix$md5 $file');
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
    final dir = Directory(_config.resolveSubDir(_config.patchCpwDir, type));
    if (!dir.existsSync()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.inc')) {
        final name = path.basename(entity.path);
        final match = RegExp(r'v-(\d+)\.inc').firstMatch(name);

        if (match != null) {
          final fromRev = int.parse(match.group(1)!);

          if (fromRev < minRev || fromRev >= currentRev) {
            await entity.delete();
          }
        }
      }
    }
  }

  int _calculateTotalSize(List<Map<String, dynamic>> files, int from, int to) {
    return files.where((f) {
      final rev = Utils.parseInt(f['revision']);
      return rev > from && rev <= to;
    }).fold<int>(0, (sum, f) {
      final size = Utils.parseInt(f['size']);
      return sum + size;
    });
  }

  /// Path to incremental patch.
  /// Example: /app/files/CPW/element/v-3.inc
  String _getPatchPath(String type, int fromRev) =>
      path.join(_config.resolveSubDir(_config.patchCpwDir, type), 'v-$fromRev.inc');

  /// Example: /app/files/CPW/element/files.md5
  String _getManifestPath(String type) =>
      path.join(_config.resolveSubDir(_config.patchCpwDir, type), 'files.md5');

  /// Example: /app/files/CPW/element/version
  String _getVersionPath(String type) =>
      path.join(_config.resolveSubDir(_config.patchCpwDir, type), 'version');
}