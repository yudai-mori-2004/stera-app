/// Enumeration of ARCore tracking states.
enum ArTrackingState {
  tracking,
  paused,
  stopped;

  static ArTrackingState fromString(String value) {
    switch (value) {
      case "TRACKING":
        return tracking;
      case "PAUSED":
        return paused;
      case "STOPPED":
        return stopped;
      default:
        throw StateError("Unknown native AR tracking state: $value");
    }
  }
}

extension ArTrackingStateLabel on ArTrackingState {
  String get label => switch (this) {
    ArTrackingState.tracking => "TRACKING",
    ArTrackingState.paused => "PAUSED",
    ArTrackingState.stopped => "STOPPED",
  };
}
