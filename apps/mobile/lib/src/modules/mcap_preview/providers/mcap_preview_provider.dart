import "dart:io";

import "package:flutter/foundation.dart";
import "package:path/path.dart" as p;
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";
import "package:stera/src/services/mcap_reader/mcap_reader.dart";

/// Opens a session's MCAP and exposes its topic list + metadata records for
/// the preview page. Owns the [McapReader] — the topic player borrows it, so
/// this provider must outlive any player page pushed on top.
///
/// Takes either the MCAP file directly ([mcapPath]) or a session directory
/// ([sessionDir]) to scan for one.
class McapPreviewProvider extends ChangeNotifier {
  McapPreviewProvider({this.sessionDir, this.mcapPath})
      : assert(sessionDir != null || mcapPath != null);

  final String? sessionDir;
  final String? mcapPath;

  McapReader? _reader;
  McapReader? get reader => _reader;

  bool isLoading = true;
  String? error;
  List<McapTopicInfo> topics = const [];
  List<McapMetadataIndex> metadataIndexes = const [];
  int fileSizeBytes = 0;

  bool _disposed = false;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final path = mcapPath ?? await _findMcapFile(sessionDir!);
      if (path == null) {
        throw const McapReadException("No MCAP file found in this recording");
      }
      fileSizeBytes = await File(path).length();
      final reader = await McapReader.open(path);
      if (_disposed) {
        await reader.close();
        return;
      }
      _reader = reader;
      topics = reader.topics;
      metadataIndexes = reader.metadataIndexes;
    } on McapReadException catch (e) {
      error = e.message;
    } catch (e) {
      error = "Failed to open MCAP: $e";
    }
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, String>> readMetadata(McapMetadataIndex index) {
    final reader = _reader;
    if (reader == null) {
      throw const McapReadException("Reader is not open");
    }
    return reader.readMetadata(index);
  }

  static Future<String?> _findMcapFile(String sessionDir) async {
    final dir = Directory(sessionDir);
    if (!await dir.exists()) return null;
    String? fallback;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith(".mcap")) continue;
      if (name.startsWith("session_data_")) return entity.path;
      fallback ??= entity.path;
    }
    return fallback;
  }

  @override
  void dispose() {
    _disposed = true;
    _reader?.close();
    super.dispose();
  }
}
