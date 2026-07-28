/// Model class to hold duplicate video information
class DuplicateVideoInfo {
  final String uri;
  final String? fileName;
  final int? fileSize;
  final int? durationMs;
  final String? thumbnailPath;

  DuplicateVideoInfo({
    required this.uri,
    this.fileName,
    this.fileSize,
    this.durationMs,
    this.thumbnailPath,
  });

  String get displayName {
    if (fileName != null && fileName!.isNotEmpty) {
      return fileName!;
    }
    try {
      final parsedUri = Uri.parse(uri);
      if (parsedUri.pathSegments.isNotEmpty) {
        return parsedUri.pathSegments.last;
      }
    } catch (_) {}
    return uri;
  }

  String get formattedSize {
    if (fileSize == null) return "";
    final kb = fileSize! / 1024;
    if (kb < 1024) {
      return "${kb.toStringAsFixed(1)} KB";
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return "${mb.toStringAsFixed(1)} MB";
    }
    final gb = mb / 1024;
    return "${gb.toStringAsFixed(2)} GB";
  }

  String get formattedDuration {
    if (durationMs == null) return "";
    final totalSeconds = durationMs! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }
}
