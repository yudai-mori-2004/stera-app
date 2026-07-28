/// Formatting helpers for the upload estimate module.
library;

/// Format an estimated upload duration into a friendly, approximate label.
/// Examples: "under a minute", "about 4 min", "about 1 hr 20 min".
String formatEta(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) return "under a minute";

  final totalMinutes = (totalSeconds / 60).round();
  if (totalMinutes < 60) return "about $totalMinutes min";

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) {
    return "about $hours hr";
  }
  return "about $hours hr $minutes min";
}

/// Compact ETA label for tight UI like the upload tile.
/// Examples: "<1m left", "12m left", "1h 20m left".
String formatEtaShort(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) return "<1m left";

  final totalMinutes = (totalSeconds / 60).round();
  if (totalMinutes < 60) return "${totalMinutes}m left";

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) return "${hours}h left";
  return "${hours}h ${minutes}m left";
}
