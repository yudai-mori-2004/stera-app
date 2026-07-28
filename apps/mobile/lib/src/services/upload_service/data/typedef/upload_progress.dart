/// Progress data emitted during file upload.
///
/// Contains:
/// - [uploadId]: The database ID of the upload
/// - [current]: Number of chunks completed
/// - [total]: Total number of chunks
/// - [progress]: Percentage progress (0-100)
/// - [videoIndex]: Current video number being uploaded (1-indexed)
/// - [totalVideos]: Total number of videos in the upload queue
typedef UploadProgress = ({
  int uploadId,
  int current,
  int total,
  int progress,
  int videoIndex,
  int totalVideos,
});
