import "dart:convert";
import "dart:io";

import "package:stera/src/services/recordings_service/data/models/recording_session.dart";
import "package:stera/src/services/upload_service/utils/mcap_finalization.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

class RecordingsService {
  static Future<Directory> _sessionsRootDir() async {
    // iOS writes sessions to Documents/ar_sessions (ArRecorderImpl.swift), which
    // is also what `UIFileSharingEnabled` exposes in Files.app. Android writes to
    // getExternalFilesDir(null)/ar_sessions (ArRecorderImpl.kt), which is what
    // getExternalStorageDirectory() resolves to — and which *throws* on iOS, so
    // this branch is what makes the recordings list work there at all.
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory())!
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, "ar_sessions"));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<List<RecordingSession>> listSessions() async {
    final root = await _sessionsRootDir();
    if (!await root.exists()) return const [];

    final entries = await root.list(followLinks: false).toList();
    final sessions = <RecordingSession>[];
    for (final entity in entries) {
      if (entity is! Directory) continue;
      final dirName = p.basename(entity.path);
      if (!dirName.startsWith("session_")) continue;

      final videoFile = await _findVideoFile(entity);
      // metadata.json is copied to the session root after spatial_data.zip is created
      // Fall back to spatial_data/metadata.json for older sessions
      final metadataFile = File(p.join(entity.path, "metadata.json"));
      final metadataFileLegacy = File(
        p.join(entity.path, "spatial_data", "metadata.json"),
      );
      final spatialDataZip = File(p.join(entity.path, "spatial_data.zip"));
      // Legacy paths for sessions recorded before the zip refactor
      final spatialDataDir = Directory(p.join(entity.path, "spatial_data"));
      final depthDir = Directory(p.join(spatialDataDir.path, "depth"));
      final depthZip = File(p.join(spatialDataDir.path, "depth.zip"));

      final resolvedMetadataFile = await metadataFile.exists()
          ? metadataFile
          : metadataFileLegacy;
      final metadata = await _readMetadata(resolvedMetadataFile);
      final durationSeconds =
          (metadata["session_duration_seconds"] as num?)?.toDouble() ??
          (metadata["durationSeconds"] as num?)?.toDouble() ??
          0.0;
      final frameCount =
          (metadata["total_video_frames_encoded"] as num?)?.toInt() ??
          (metadata["framesRecorded"] as num?)?.toInt() ??
          0;
      final imuSamples =
          (metadata["total_imu_samples"] as num?)?.toInt() ??
          (metadata["imuSamples"] as num?)?.toInt() ??
          0;

      // New sessions: depth frames are inside spatial_data.zip
      // Legacy sessions: depth/ directory or depth.zip inside spatial_data/
      final hasSpatialDataZip =
          await spatialDataZip.exists() && (await spatialDataZip.length()) > 0;
      final hasDepthDir =
          await depthDir.exists() &&
          (await depthDir.list(followLinks: false).isEmpty) == false;
      final hasDepthZip =
          await depthZip.exists() && (await depthZip.length()) > 0;
      final hasDepth = hasSpatialDataZip || hasDepthDir || hasDepthZip;
      final recordedAt = _parseSessionTimestamp(dirName);
      final sizeBytes = await _sessionSizeBytes(entity, videoFile);
      final thumbnailFile = File(p.join(entity.path, "thumbnail.jpg"));
      final hasThumbnail = await thumbnailFile.exists();

      sessions.add(
        RecordingSession(
          thumbnailPath: hasThumbnail ? thumbnailFile.path : null,
          directoryName: dirName,
          fullPath: entity.path,
          recordedAt: recordedAt,
          durationSeconds: durationSeconds,
          frameCount: frameCount,
          imuSamples: imuSamples,
          hasVideo: await videoFile.exists(),
          hasDepth: hasDepth,
          sizeBytes: sizeBytes,
        ),
      );
    }

    sessions.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sessions;
  }

  static Future<bool> deleteSession(String sessionDirName) async {
    final root = await _sessionsRootDir();
    final dir = Directory(p.join(root.path, sessionDirName));
    if (!await dir.exists()) return true;
    try {
      await dir.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<int> deleteSessions(List<String> sessionDirNames) async {
    var deleted = 0;
    for (final session in sessionDirNames) {
      final ok = await deleteSession(session);
      if (ok) deleted++;
    }
    return deleted;
  }

  static Future<int> getTotalStorageUsed() async {
    final sessions = await listSessions();
    return sessions.fold<int>(0, (sum, item) => sum + item.sizeBytes);
  }

  /// The session's mcap file, or null when the directory holds none.
  /// Prefers the recorder's `session_data_*.mcap`, falling back to any `.mcap`,
  /// matching how [McapPreviewProvider] resolves a file to open.
  static File? findMcapFile(String sessionDirPath) {
    final dir = Directory(sessionDirPath);
    if (!dir.existsSync()) return null;
    try {
      final mcaps = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.endsWith(".mcap"))
          .toList();
      if (mcaps.isEmpty) return null;
      return mcaps.firstWhere(
        (f) => f.uri.pathSegments.last.startsWith("session_data_"),
        orElse: () => mcaps.first,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether the session's mcap has been closed out by the native writer and is
  /// therefore safe to open with `McapReader`. False for a still-growing file,
  /// a crash-truncated one, or a directory with no mcap at all.
  static Future<bool> isSessionFinalized(String sessionDirPath) async {
    final mcap = findMcapFile(sessionDirPath);
    if (mcap == null) return false;
    return McapFinalization.isFinalized(mcap);
  }

  static Future<Map<String, dynamic>> _readMetadata(File metadataFile) async {
    if (!await metadataFile.exists()) return const {};
    try {
      final raw = await metadataFile.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) {
        return parsed.map((key, value) => MapEntry(key.toString(), value));
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }

  static DateTime _parseSessionTimestamp(String dirName) {
    try {
      final ts = dirName.replaceFirst("session_", "");
      if (ts.length != 15) return DateTime.fromMillisecondsSinceEpoch(0);
      final yyyy = int.parse(ts.substring(0, 4));
      final mm = int.parse(ts.substring(4, 6));
      final dd = int.parse(ts.substring(6, 8));
      final hh = int.parse(ts.substring(9, 11));
      final min = int.parse(ts.substring(11, 13));
      final ss = int.parse(ts.substring(13, 15));
      return DateTime(yyyy, mm, dd, hh, min, ss);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Computes the meaningful size of a session directory by summing only
  /// the video file, spatial_data.zip, and metadata.json — skipping raw
  /// CSV/binary files that are already included in the zip.
  static Future<int> _sessionSizeBytes(Directory dir, File videoFile) async {
    var bytes = 0;
    if (await videoFile.exists()) {
      bytes += await videoFile.length();
    }
    final spatialZip = File(p.join(dir.path, "spatial_data.zip"));
    if (await spatialZip.exists()) {
      bytes += await spatialZip.length();
    }
    final metadataFile = File(p.join(dir.path, "metadata.json"));
    if (await metadataFile.exists()) {
      bytes += await metadataFile.length();
    }
    return bytes;
  }

  /// Finds the video file in a session directory.
  /// Supports both new timestamped filenames (video_YYYYMMDD_HHMMSS.mp4)
  /// and the legacy hardcoded name (video.mp4).
  static Future<File> _findVideoFile(Directory sessionDir) async {
    // Async directory scan so listing N sessions doesn't block the main isolate
    // with N synchronous listSync calls.
    await for (final file in sessionDir.list(followLinks: false)) {
      if (file is! File) continue;
      final name = p.basename(file.path);
      if (name.startsWith("video") && name.endsWith(".mp4")) {
        return file;
      }
    }
    // Fallback to legacy name (won't exist, but caller checks .exists())
    return File(p.join(sessionDir.path, "video.mp4"));
  }
}
