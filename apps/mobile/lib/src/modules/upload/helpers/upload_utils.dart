/// Utility functions for the upload module.
///
/// Provides formatting helpers and file name utilities
/// used across upload UI components.
library;

/// Format duration from milliseconds to MM:SS or HH:MM:SS
String formatDuration(int? durationMs) {
  if (durationMs == null) return "--:--";
  final seconds = (durationMs / 1000).floor();
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;

  if (hours > 0) {
    return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }
  return "${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
}

/// Format file size to human readable format
String formatFileSize(int? bytes) {
  if (bytes == null) return "-- MB";
  final mb = bytes / (1024 * 1024);
  final gb = bytes / (1024 * 1024 * 1024);

  if (gb >= 1) {
    return "${gb.toStringAsFixed(2)} GB";
  }
  return "${mb.toStringAsFixed(2)} MB";
}

// Note: truncateFileName has been moved to
// lib/src/core/common/formatters/format_file_name.dart
// Please import from there instead.
