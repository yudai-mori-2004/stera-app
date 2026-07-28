/// Lifecycle of one part within a session.
enum PartState {
  /// Chunk plan entry exists; no presigned URL yet.
  planned,

  /// A presigned URL (with recorded expiry) is assigned.
  urlReady,

  /// The window manager extracted a temp chunk and resumed the upload task.
  inFlight,

  /// 200 + ETag received and journaled.
  uploaded;

  bool get isUploaded => this == PartState.uploaded;

  /// Anything not yet `uploaded` still needs to be transferred.
  bool get needsTransfer => this != PartState.uploaded;
}
