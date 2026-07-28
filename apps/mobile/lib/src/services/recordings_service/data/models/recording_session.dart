class RecordingSession {
  final String directoryName;
  final String fullPath;
  final DateTime recordedAt;
  final double durationSeconds;
  final int frameCount;
  final int imuSamples;
  final bool hasVideo;
  final bool hasDepth;

  /// Whether the session's MCAP already carries hand poses — keyed off the
  /// sidecar marker files, a cheap File.exists() like the flags
  /// above. Drives the tile icon and the Detect/Refresh label.
  final int sizeBytes;

  /// Absolute path to the session's `thumbnail.jpg`, or null when the recorder
  /// didn't write one. An absolute path is safe here because it is resolved on
  /// every listing rather than persisted — unlike the upload table, which keeps
  /// a `documents://` URI because iOS container UUIDs change between launches.
  final String? thumbnailPath;

  const RecordingSession({
    required this.directoryName,
    required this.fullPath,
    required this.recordedAt,
    required this.durationSeconds,
    required this.frameCount,
    required this.imuSamples,
    required this.hasVideo,
    required this.hasDepth,
    required this.sizeBytes,
    this.thumbnailPath,
  });
}
