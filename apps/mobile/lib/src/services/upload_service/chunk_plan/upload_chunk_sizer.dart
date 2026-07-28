/// Chooses the multipart chunk size for a file (Phase 4 — 50 GB+ enablement).
///
/// **Uniform within a file** (R2 requires equal-size parts except the last) and
/// frozen on the session row at `preparing`, so resume never recomputes it.
/// Two tiers:
///   - **≤ 60 GiB:** adaptive — aim for ~[targetParts] parts, rounded up to an
///     8 MiB boundary, clamped to `[minChunk, maxChunk]` (16–64 MiB). So 40–60 GiB
///     land at the 64 MiB cap; small/mid files stay small.
///   - **> 60 GiB:** a fixed **128 MiB** ([hugeFileChunk]) part — keeps the part
///     count and per-part/presign overhead low for very large files, while
///     staying a modest unit for URLSession (re-send cost, idle-timeout margin).
abstract final class UploadChunkSizer {
  /// 16 MiB — above R2's 5 MiB floor; keeps part counts low for mid-size files.
  static const int minChunk = 16 * 1024 * 1024;

  /// 64 MiB — adaptive cap for files up to [hugeFileThresholdBytes].
  static const int maxChunk = 64 * 1024 * 1024;

  /// Files larger than 60 GiB switch to the fixed [hugeFileChunk].
  static const int hugeFileThresholdBytes = 60 * 1024 * 1024 * 1024;

  /// 128 MiB — fixed part size for files over [hugeFileThresholdBytes].
  /// Window temp disk is then 8 × 128 = 1 GiB, negligible next to a 60 GB+ source.
  static const int hugeFileChunk = 128 * 1024 * 1024;

  /// Target part count, well under R2's 10,000 ceiling.
  static const int targetParts = 600;

  static const int _alignment = 8 * 1024 * 1024; // 8 MiB

  static int chooseChunkSize(int fileSize) {
    if (fileSize <= 0) return minChunk;

    // Very large files: a fixed 128 MiB part. (e.g. 100 GiB → 800 parts.)
    if (fileSize > hugeFileThresholdBytes) return hugeFileChunk;

    final raw = (fileSize + targetParts - 1) ~/ targetParts; // ceil(size/target)
    final aligned = ((raw + _alignment - 1) ~/ _alignment) * _alignment;
    return aligned.clamp(minChunk, maxChunk);
  }
}
