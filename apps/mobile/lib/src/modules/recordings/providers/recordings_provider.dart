import "dart:async";

import "package:stera/src/services/recordings_service/data/models/recording_session.dart";
import "package:stera/src/services/recordings_service/recordings_service.dart";
import "package:flutter/foundation.dart";

class RecordingsProvider extends ChangeNotifier {
  List<RecordingSession> _sessions = const [];
  List<RecordingSession> get sessions => _sessions;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _isSelectionMode = false;
  bool get isSelectionMode => _isSelectionMode;

  final Set<String> _selectedSessionIds = <String>{};
  Set<String> get selectedSessionIds => _selectedSessionIds;

  int _totalStorageUsedBytes = 0;
  int get totalStorageUsedBytes => _totalStorageUsedBytes;

  String? _finalizingDir;

  /// True while [session]'s mcap is still being closed out by the native
  /// recorder. `McapReader` needs a finalized file, so the preview tap is
  /// disabled until the trailing magic lands.
  bool isFinalizing(RecordingSession session) =>
      _finalizingDir != null && session.fullPath == _finalizingDir;

  /// Polls until [sessionDir]'s mcap carries its trailing magic.
  ///
  /// The session is already listed by then — `metadata.json` is written *before*
  /// the mcap footer, so a fresh recording shows plausible duration and frame
  /// counts while the file is still growing. Only the tap is gated, not the row.
  ///
  /// Same cadence and cap as the upload path (500ms × 120). For a long recording
  /// the footer write can exceed a minute, so a timeout here is not a failure —
  /// it just means "not previewable yet", and the tile becomes tappable anyway
  /// rather than spinning forever.
  Future<void> trackFinalization(String sessionDir) async {
    _finalizingDir = sessionDir;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 120; attempt++) {
        if (await RecordingsService.isSessionFinalized(sessionDir)) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      _finalizingDir = null;
      // Sizes and durations are only trustworthy once the footer has landed.
      await loadSessions();
    }
  }

  Future<void> loadSessions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await RecordingsService.listSessions();
      // Derive the total from the sessions we just loaded rather than calling
      // getTotalStorageUsed(), which re-runs listSessions() and doubles all the
      // per-session file I/O (listSync + exists/length + metadata reads).
      _totalStorageUsedBytes =
          _sessions.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteSession(String dirName) async {
    final ok = await RecordingsService.deleteSession(dirName);
    if (!ok) {
      _error = "Failed to delete recording.";
      notifyListeners();
      return;
    }
    _selectedSessionIds.remove(dirName);
    await loadSessions();
  }

  Future<void> deleteSelectedSessions() async {
    final ids = _selectedSessionIds.toList(growable: false);
    if (ids.isEmpty) return;
    final deleted = await RecordingsService.deleteSessions(ids);
    if (deleted != ids.length) {
      _error = "Some recordings could not be deleted.";
    }
    _selectedSessionIds.clear();
    _isSelectionMode = false;
    await loadSessions();
  }

  void toggleSelection(String dirName) {
    if (_selectedSessionIds.contains(dirName)) {
      _selectedSessionIds.remove(dirName);
    } else {
      _selectedSessionIds.add(dirName);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedSessionIds
      ..clear()
      ..addAll(_sessions.map((e) => e.directoryName));
    notifyListeners();
  }

  void clearSelection() {
    _selectedSessionIds.clear();
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedSessionIds.clear();
    }
    notifyListeners();
  }
}
