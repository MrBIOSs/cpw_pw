import 'package:path/path.dart' as path;

final class SafePathResolver {
  static String resolveInsideBase({
    required String baseDir,
    required String unsafePath,
  }) {
    if (path.isAbsolute(unsafePath)) {
      throw Exception('Absolute paths are forbidden');
    }

    final resolvedBase = path.normalize(path.absolute(baseDir));
    final resolvedTarget = path.normalize(
      path.absolute(
        path.join(resolvedBase, unsafePath),
      ),
    );

    if (!path.isWithin(resolvedBase, resolvedTarget) &&
        resolvedBase != resolvedTarget) {
      throw Exception('Path traversal detected: $unsafePath');
    }

    return resolvedTarget;
  }
}