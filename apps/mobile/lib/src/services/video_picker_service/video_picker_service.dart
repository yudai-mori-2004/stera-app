import "dart:io";
import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/content_uri_service/content_uri_service.dart";
import "package:stera/src/services/video_picker_service/channels/video_metadata_method_channels.dart";
import "package:stera/src/services/video_picker_service/channels/video_picker_method_channels.dart";
import "package:drift/drift.dart";

class VideoPickerService {
  VideoPickerService._internal();
  static final VideoPickerService _instance = VideoPickerService._internal();
  static VideoPickerService get instance => _instance;

  UploadDb get db => UploadDb.instance;

  Future<List<String>?> pickVideos() async {
    return await VideoPickerMethodChannels.pickVideos();
  }

  Future<(Upload?, Failure?)> createUpload({
    required String uriString,
    required List<VideoMetadata> existingVideos,
    String? parentTaskId,
    String? parentTaskName,
    String? subtaskId,
    String? subtaskName,
  }) async {
    final uri = Uri.parse(uriString);
    final isContentUri = uri.scheme == "content";
    final isFileUri = uri.scheme == "file";
    // appsupport:// is our custom scheme for iOS files in Application Support directory
    // that survive app container UUID changes
    final isAppSupportUri = uri.scheme == "appsupport";

    final doesVideoExist = await db.checkIfExists(
      filePath: uriString,
      status: [
        UploadStatus.uploading,
        UploadStatus.notStarted,
        UploadStatus.completed,
        UploadStatus.pending,
        UploadStatus.paused,
      ],
    );

    if (doesVideoExist) return (null, null);

    // For iOS file:// URLs and appsupport:// URLs, we use the same ContentUriService
    // (which calls iOS SecurityScopedURLHelper)
    final isSecurityScopedUri =
        isContentUri || isAppSupportUri || (Platform.isIOS && isFileUri);

    if (isSecurityScopedUri) {
      final hasPermission = await ContentUriService.hasPermission(uri);

      if (!hasPermission) {
        final granted = await ContentUriService.takePersistentPermission(uri);
        if (!granted) {
          return (
            null,
            Failure(
              code: ErrorType.unauthorized,
              message: "Permission denied for $uriString",
            ),
          );
        }
      }
    }

    int fileSize;
    String? fileName;
    String? mimeType;

    if (isSecurityScopedUri) {
      fileSize = await ContentUriService.getFileSize(uri);
      final fileMetadata = await ContentUriService.getFileMetadata(uri);
      fileName = fileMetadata?["name"];
      mimeType = fileMetadata?["mimeType"];
    } else {
      // For local file paths (e.g. recorded videos)
      String filePath = uriString;
      if (uri.scheme == "file") {
        filePath = uri.toFilePath();
      }
      final file = File(filePath);
      if (await file.exists()) {
        fileSize = await file.length();
        fileName = uri.pathSegments.last;
        // Simple extension check for mime type
        if (fileName.toLowerCase().endsWith(".mp4")) {
          mimeType = "video/mp4";
        } else if (fileName.toLowerCase().endsWith(".mov")) {
          mimeType = "video/quicktime";
        }
      } else {
        return (
          null,
          Failure(
            code: ErrorType.fileNotFound,
            message: "File not found: $uriString",
          ),
        );
      }
    }

    // Try to refine metadata (especially filename) via native video helper.
    final videoMetadata = await VideoMetadataMethodChannels.getVideoMetadata(
      Uri.parse(uriString),
    );
    final metadataName = videoMetadata?["name"] as String?;
    if (metadataName != null && metadataName.isNotEmpty) {
      fileName = metadataName;
    }
    mimeType ??= videoMetadata?["mimeType"] as String?;

    // Runs on a Kotlin background thread, so no isolate hop is needed here.
    final thumbnail = await VideoMetadataMethodChannels.extractThumbnail(
      Uri.parse(uriString),
    );

    final duration = await VideoMetadataMethodChannels.getVideoDuration(
      Uri.parse(uriString),
    );

    bool isExistingVideoDup = false;

    for (VideoMetadata vid in existingVideos) {
      if (vid.title == fileName && vid.duration == duration) {
        isExistingVideoDup = true;
      }
    }

    if (isExistingVideoDup) {
      return (
        null,
        Failure(
          code: ErrorType.duplicateUpload,
          message: ErrorType.duplicateUpload.message,
        ),
      );
    }

    final UploadsCompanion uploadCompanion = UploadsCompanion.insert(
      filepath: uriString,
      filesize: Value(fileSize),
      thumnbnail: Value(thumbnail),
      durationMs: Value(duration != null ? duration * 1000 : null),
      createdAt: Value(DateTime.now()),
      fileName: Value(fileName),
      mimeType: Value(mimeType),
      status: const Value(UploadStatus.notStarted),
      taskId: Value(parentTaskId),
      taskName: Value(parentTaskName),
      subtaskId: Value(subtaskId),
      subtaskName: Value(subtaskName),
    );

    final upload = await db.add(uriString, uploadCompanion: uploadCompanion);

    // Note: We don't release permission here because we need access for future uploads
    // The bookmark will be released when the upload is deleted or completed

    return (upload, null);
  }
}
