import "dart:io";

import "package:path_provider/path_provider.dart";

/// Resolves stored file paths that use the `documents://` custom scheme
/// to absolute paths using the current app Documents directory.
///
/// On iOS, the app container UUID changes between reinstalls/restarts,
/// invalidating absolute paths. The `documents://` scheme stores paths
/// relative to the Documents directory so they survive UUID changes.
///
/// Example:
///   `documents://ar_sessions/session_xxx/file.mcap`
///   → `/var/mobile/Containers/Data/Application/<current-UUID>/Documents/ar_sessions/session_xxx/file.mcap`
class ResolveFilePath {
  static String? _cachedDocsPath;

  /// Resolves a stored path to an absolute path.
  /// If the path uses `documents://`, it's resolved against the current
  /// Documents directory. Otherwise, it's returned as-is.
  static Future<String> resolve(String storedPath) async {
    if (!storedPath.startsWith("documents://")) return storedPath;

    final docsDir = await _getDocsPath();
    final relativePath = storedPath.substring("documents://".length);
    return "$docsDir/$relativePath";
  }

  /// Converts an absolute Documents path to a `documents://` relative path.
  /// Returns the original path if it's not inside the Documents directory.
  static Future<String> toDocumentsUri(String absolutePath) async {
    final docsDir = await _getDocsPath();
    if (absolutePath.startsWith("$docsDir/")) {
      final relativePath = absolutePath.substring("$docsDir/".length);
      return "documents://$relativePath";
    }
    return absolutePath;
  }

  /// Attempts to fix an absolute iOS path that has a stale container UUID.
  /// Looks for `/Documents/` in the path and reconstructs using current dir.
  /// Returns null if the path can't be fixed or the file doesn't exist.
  static Future<String?> tryFixStalePath(String absolutePath) async {
    if (!Platform.isIOS) return null;

    final docsMarker = "/Documents/";
    final docsIndex = absolutePath.indexOf(docsMarker);
    if (docsIndex == -1) return null;

    final relativePath =
        absolutePath.substring(docsIndex + docsMarker.length);
    final docsDir = await _getDocsPath();
    final resolvedPath = "$docsDir/$relativePath";

    if (await File(resolvedPath).exists()) {
      return resolvedPath;
    }
    return null;
  }

  static Future<String> _getDocsPath() async {
    if (_cachedDocsPath != null) return _cachedDocsPath!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedDocsPath = dir.path;
    return _cachedDocsPath!;
  }
}
