import "package:intl/intl.dart";

extension DurationX on Duration {
  String get formatHms {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);

    final h = Intl.message("h", name: "hours_unit");
    final m = Intl.message("m", name: "minutes_unit");

    if (hours > 0) {
      return "$hours$h $minutes$m";
    }
    return "$minutes$m";
  }

  String get formatHmsWithSeconds {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);

    final h = Intl.message("h", name: "hours_unit");
    final m = Intl.message("m", name: "minutes_unit");
    final s = Intl.message("s", name: "seconds_unit");

    if (hours > 0) {
      return "$hours$h $minutes$m $seconds$s";
    }

    if (minutes > 0) {
      return "$minutes$m $seconds$s";
    }

    return "$seconds$s";
  }
}

extension IntX on int {
  /// Total seconds as a compact label (e.g. `45s`, `3m 12s`, `1h 2m 5s`).
  String get formatDuration => Duration(seconds: this).formatHmsWithSeconds;
}

extension DateTimeX on DateTime {
  String get formatDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(year, month, day);

    if (date == today) {
      return "Today";
    } else if (date == yesterday) {
      return "Yesterday";
    } else {
      return DateFormat("dd MMM yyyy").format(this);
    }
  }

  String get formatDateTime => DateFormat("dd MMM yyyy, hh:mm a").format(this);
}
