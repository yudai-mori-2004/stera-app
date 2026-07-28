import "dart:convert";

import "package:stera/src/modules/uploaded_videos/data/uploaded_videos_status.dart";

/// Backend may return [metadata] values as JSON strings (everything stringified
/// for validation). Coerce for safe reads in [VideoMetadata.fromMap].
int? _coerceInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) {
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }
  return null;
}

double? _coerceDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }
  return null;
}

String? _coerceString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

class VideoMetadata {
  final String id;
  final String userId;
  final String title;
  final String thumbnailUrl;
  final int duration;
  final UploadedVideosStatus status;
  final String? comments;
  final int? fileSizeBytes;
  final double? rgbFps;
  final double? imuFps;
  final double? depthFps;
  final double? pointcloudFps;
  final String? resolution;
  final DateTime createdAt;

  VideoMetadata({
    required this.id,
    required this.userId,
    required this.title,
    required this.thumbnailUrl,
    required this.duration,
    required this.status,
    this.comments,
    this.fileSizeBytes,
    this.rgbFps,
    this.imuFps,
    this.depthFps,
    this.pointcloudFps,
    this.resolution,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "user_id": userId,
      "title": title,
      "thumbnail_url": thumbnailUrl,
      "duration": duration,
      "status": status.id,
      "comments": comments,
      "file_size_bytes": fileSizeBytes,
      "rgb_fps": rgbFps,
      "imu_fps": imuFps,
      "depth_fps": depthFps,
      "pointcloud_fps": pointcloudFps,
      "resolution": resolution,
      "created_at": createdAt.toIso8601String(),
    };
  }

  factory VideoMetadata.fromMap(Map<String, dynamic> map) {
    final rawMetadata = map["metadata"];
    final metadata = rawMetadata is Map
        ? rawMetadata.cast<String, dynamic>()
        : <String, dynamic>{};

    return VideoMetadata(
      id: _coerceString(map["id"]) ?? "",
      userId: _coerceString(map["uploadedByProfileId"]) ?? "",
      title: _coerceString(map["originalFilename"]) ?? "",
      thumbnailUrl: _coerceString(map["thumbnailUrl"]) ?? "",
      duration: _coerceInt(map["durationSeconds"]) ?? 0,
      status: UploadedVideosStatus.values.firstWhere(
        (e) => e.id == (_coerceString(map["status"]) ?? ""),
        orElse: () => UploadedVideosStatus.all,
      ),
      comments: null,
      fileSizeBytes:
          _coerceInt(map["fileSizeBytes"]) ??
          _coerceInt(metadata["estimated_dataset_size_bytes"]),
      rgbFps:
          _coerceDouble(metadata["rgb_fps"]) ?? _coerceDouble(metadata["fps"]),
      imuFps: _coerceDouble(metadata["imu_fps"]),
      depthFps: _coerceDouble(metadata["depth_fps"]),
      pointcloudFps: _coerceDouble(metadata["pointcloud_fps"]),
      resolution:
          _coerceString(metadata["camera_resolution"]) ??
          _coerceString(metadata["resolution"]),
      createdAt:
          DateTime.tryParse(_coerceString(map["createdAt"]) ?? "") ??
          DateTime(2000, 1, 1),
    );
  }

  String toJson() => json.encode(toMap());

  factory VideoMetadata.fromJson(String source) =>
      VideoMetadata.fromMap(json.decode(source));
}

class VideoLists {
  final List<VideoMetadata> approved;
  final List<VideoMetadata> pending;
  final List<VideoMetadata> rejected;
  final List<VideoMetadata> all;

  VideoLists({
    required this.approved,
    required this.pending,
    required this.rejected,
    required this.all,
  });

  factory VideoLists.segregateByStatus(List<VideoMetadata> videos) {
    final approved = videos
        .where((v) => v.status == UploadedVideosStatus.approved)
        .toList();
    final pending = videos
        .where((v) => v.status == UploadedVideosStatus.pending)
        .toList();
    final rejected = videos
        .where((v) => v.status == UploadedVideosStatus.rejected)
        .toList();

    return VideoLists(
      approved: approved,
      pending: pending,
      rejected: rejected,
      all: videos,
    );
  }

  VideoLists copyWith({
    List<VideoMetadata>? approved,
    List<VideoMetadata>? pending,
    List<VideoMetadata>? rejected,
    List<VideoMetadata>? all,
  }) {
    return VideoLists(
      approved: approved ?? this.approved,
      pending: pending ?? this.pending,
      rejected: rejected ?? this.rejected,
      all: all ?? this.all,
    );
  }

  int get approvedDurationSeconds =>
      approved.fold(0, (sum, video) => sum + video.duration);

  int get pendingDurationSeconds =>
      pending.fold(0, (sum, video) => sum + video.duration);

  int get totalDurationSeconds =>
      all.fold(0, (sum, video) => sum + video.duration);
}
