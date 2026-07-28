/// Key-value persistence the recorder needs for its settings.
///
/// The host app supplies the implementation — typically a thin wrapper over
/// whatever key-value store it already uses. That keeps this package free of
/// any storage plugin and lets the recorder share the app's single store.
abstract class RecorderPreferences {
  /// Reads [key], returning [defaultValue] when absent. Implementations must
  /// support `bool` and `int`.
  T? get<T>(String key, {T? defaultValue});

  /// Writes [key]. Fire-and-forget: callers do not await.
  Future<void> set(String key, Object value);
}

/// A no-op store. Every read returns the caller's default, every write is
/// dropped — the recorder then runs on its built-in defaults.
class InMemoryRecorderPreferences implements RecorderPreferences {
  final Map<String, Object> _values = {};

  @override
  T? get<T>(String key, {T? defaultValue}) =>
      _values[key] as T? ?? defaultValue;

  @override
  Future<void> set(String key, Object value) async {
    _values[key] = value;
  }
}
