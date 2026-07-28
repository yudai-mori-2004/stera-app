/// Byte counts rendered for humans: `1536` → `"1.5 KB"`.
///
/// Uses binary (1024) steps, matching what the OS reports for file sizes.
/// [nullPlaceholder] is returned for a null [bytes] so call sites don't each
/// re-invent an empty state.
String formatBytes(int? bytes, {String nullPlaceholder = "--"}) {
  if (bytes == null) return nullPlaceholder;
  if (bytes < 1024) return "$bytes B";

  final kb = bytes / 1024;
  if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";

  final mb = kb / 1024;
  if (mb < 1024) return "${mb.toStringAsFixed(1)} MB";

  final gb = mb / 1024;
  return "${gb.toStringAsFixed(2)} GB";
}
