/// Disk-headroom check for the windowed engine (Phase 4).
///
/// The whole point of the sliding window is that disk stays bounded: at most
/// `windowSize` temp chunk files exist at once, so the upload needs only
/// `windowSize × chunkSize` (+ slack) free — **not** a second copy of the whole
/// file (the legacy "schedule everything" blow-up, T1). The pre-flight gates a
/// session on that bounded figure, so a 50 GB upload no longer needs ~100 GB
/// free. Pure math; the available-bytes reading is a thin platform seam at the
/// call site.
abstract final class UploadDiskPreflight {
  /// Bytes the in-flight window can occupy at peak.
  static int windowBytes({required int chunkSize, required int windowSize}) =>
      chunkSize * windowSize;

  /// Bytes a session needs free to run: the window plus a safety [slackBytes]
  /// (one extra chunk being extracted, FS overhead).
  static int requiredBytes({
    required int chunkSize,
    required int windowSize,
    int slackBytes = 0,
  }) =>
      windowBytes(chunkSize: chunkSize, windowSize: windowSize) + slackBytes;

  /// Whether [availableBytes] of free disk is enough to run the window.
  static bool hasHeadroom({
    required int availableBytes,
    required int chunkSize,
    required int windowSize,
    int slackBytes = 0,
  }) =>
      availableBytes >=
      requiredBytes(
        chunkSize: chunkSize,
        windowSize: windowSize,
        slackBytes: slackBytes,
      );
}
