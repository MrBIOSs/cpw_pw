import 'package:path/path.dart' as path;
import 'package:cpw_pw/core/utils/safe_path.dart';

/// Immutable patcher configuration.
/// All fields are required and validated upon upload.
final class PatcherConfig {
  const PatcherConfig({
    required this.baseDir,
    required this.dbHost,
    required this.dbPort,
    required this.dbUser,
    required this.dbPassword,
    required this.dbName,
    required this.patchPath,
    required this.patchNewDir,
    required this.patchCpwDir,
    required this.minLauncherVer,
    required this.minPatcherVer,
    required this.minElementVer,
    required this.removeFolders,
    required this.removeFiles,
    required this.addSize,
  });

  final String baseDir;

  // DB
  final String dbHost;
  final int dbPort;
  final String dbUser;
  final String dbPassword;
  final String dbName;

  // Paths (relative to the application root)
  final String patchPath;
  final String patchNewDir;
  final String patchCpwDir;

  // Minimum client versions
  final int minLauncherVer;
  final int minPatcherVer;
  final int minElementVer;

  // Behavior Flags
  final bool removeFolders;
  final bool removeFiles;
  final bool addSize;

  /// Resolves a relative path relative to the application's base directory.
  String resolvePath(String relativePath) =>
      SafePathResolver.resolveInsideBase(baseDir: baseDir, unsafePath: relativePath);

  String resolveSubDir(String subDir, String type) {
    final relative = path.join(patchPath, subDir, type);
    return resolvePath(relative);
  }

  int getMinRevForType(String type) => switch (type) {
    'element' => minElementVer,
    'launcher' => minLauncherVer,
    'patcher' => minPatcherVer,
    _ => throw ArgumentError('Unknown type: $type'),
  };
}