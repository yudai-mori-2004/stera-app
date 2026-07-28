import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/modules/uploaded_videos/data/uploaded_videos_repo.dart";
import "package:stera/src/modules/uploaded_videos/data/uploaded_videos_status.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:flutter/material.dart";

class UploadedVideosProvider extends ChangeNotifier {
  List<VideoMetadata> _videos = [];
  List<VideoMetadata> get videos => _videos;
  set videos(List<VideoMetadata> value) {
    _videos = value;
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;
  set loading(bool value) {
    _loading = value;
    notifyListeners();
  }

  UploadedVideosStatus _selectedStatus = UploadedVideosStatus.all;
  UploadedVideosStatus get selectedStatus => _selectedStatus;
  set selectedStatus(UploadedVideosStatus value) {
    _selectedStatus = value;
    notifyListeners();
  }

  List<VideoMetadata> get videosByStatus {
    final filtered = videos.where((video) {
      switch (selectedStatus) {
        case UploadedVideosStatus.all:
          return true;
        case UploadedVideosStatus.approved:
          return video.status == UploadedVideosStatus.approved;
        case UploadedVideosStatus.pending:
          return video.status == UploadedVideosStatus.pending;
        case UploadedVideosStatus.rejected:
          return video.status == UploadedVideosStatus.rejected;
        case UploadedVideosStatus.flagged:
          return video.status == UploadedVideosStatus.flagged;
      }
    }).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  List<VideoMetadata> get filteredVideos => videosByStatus;

  Future<Failure?> getUploadedVideos() async {
    loading = true;
    final (res, err) = await UploadedVideosRepo.getUploadedVideos();
    loading = false;

    if (err != null) return err;

    final existingIds = videos.map((v) => v.id).toSet();
    final newVideos = res!
        .where((video) => !existingIds.contains(video.id))
        .toList();
    videos = [..._videos, ...newVideos];

    return null;
  }

  bool get hasVideos => videos.isNotEmpty;

  List<VideoMetadata> get recentVideos {
    final sortedVideos = [...videos]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sortedVideos.take(4).toList();
  }

  Future<Failure?> refresh() async {
    videos = [];
    return await getUploadedVideos();
  }

  VideoMetadata? getVideoById(String id) {
    final video = videos.firstWhere((video) => video.id == id);
    return video;
  }

  void reset() {
    videos = [];
    loading = false;
    selectedStatus = UploadedVideosStatus.all;
  }
}
