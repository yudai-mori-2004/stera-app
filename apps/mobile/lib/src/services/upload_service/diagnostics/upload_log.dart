import "dart:async";
import "dart:developer" as dev;

/// Severity of an [UploadLogEntry]. Kept tiny on purpose — the dev page colour
/// codes by this, and it doubles as a filter.
enum UploadLogLevel { debug, info, warn, error }

/// One line in the upload diagnostics feed.
class UploadLogEntry {
  UploadLogEntry({
    required this.time,
    required this.tag,
    required this.message,
    required this.level,
  });

  final DateTime time;
  final String tag;
  final String message;
  final UploadLogLevel level;

  /// `12:34:56.789 [tag] message`
  String format() {
    final t = time;
    String two(int n) => n.toString().padLeft(2, "0");
    final ms = t.millisecond.toString().padLeft(3, "0");
    return "${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms "
        "[$tag] $message";
  }
}

/// A release-safe, in-memory ring buffer for upload diagnostics.
///
/// `dart:developer`'s `log` and `debugPrint` are stripped/no-op in release
/// builds — which is exactly where uploads are tested — so the windowed engine's
/// breadcrumbs are invisible there. [UploadLog] keeps the last [_maxEntries]
/// lines in memory (works in every build mode) and streams new lines to the
/// upload dev page, while still forwarding to `dev.log` so the debug console is
/// unchanged.
///
/// Singleton; safe to call from any isolate-free context. The buffer is bounded
/// so it never grows without limit during a long multi-GB upload.
class UploadLog {
  UploadLog._();
  static final UploadLog instance = UploadLog._();

  static const int _maxEntries = 500;

  final List<UploadLogEntry> _entries = [];
  final StreamController<UploadLogEntry> _controller =
      StreamController<UploadLogEntry>.broadcast();

  /// Newest-last snapshot of the buffered entries.
  List<UploadLogEntry> get entries => List.unmodifiable(_entries);

  /// Fires once per appended entry.
  Stream<UploadLogEntry> get stream => _controller.stream;

  /// Append a line. Also forwards to `dev.log` (no-op in release) so existing
  /// debug-console workflows keep working.
  static void add(
    String tag,
    String message, {
    UploadLogLevel level = UploadLogLevel.info,
  }) =>
      instance._add(tag, message, level);

  void _add(String tag, String message, UploadLogLevel level) {
    final entry = UploadLogEntry(
      time: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    dev.log(message, name: tag);
    if (!_controller.isClosed) _controller.add(entry);
  }

  /// Drop every buffered line (the dev page's "clear" action).
  void clear() => _entries.clear();

  /// All buffered lines joined for copy-to-clipboard.
  String dump() => _entries.map((e) => e.format()).join("\n");
}
