import "package:intl/intl.dart";

/// 1234567 → "1,234,567" — large message counts are unreadable without
/// separators.
String formatMessageCount(int count) =>
    NumberFormat.decimalPattern().format(count);

/// 75.3 → "1:15.3" — playback clock for the topic players.
String formatPlaybackSeconds(double seconds) {
  final total = seconds.clamp(0, 86400);
  final m = total ~/ 60;
  final s = total % 60;
  return "$m:${s.toStringAsFixed(1).padLeft(4, "0")}";
}
