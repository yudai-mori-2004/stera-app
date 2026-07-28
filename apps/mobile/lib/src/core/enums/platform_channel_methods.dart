import "platform_channels.dart";

/// All available methods for the ContentUriHelper platform channel.
enum ContentUriHelperMethod {
  takePersistentPermission("takePersistentPermission"),
  releasePersistentPermission("releasePersistentPermission"),
  hasPermission("hasPermission"),
  getFileSize("getFileSize"),
  getFileMetadata("getFileMetadata"),
  readChunk("readChunk");

  final String methodName;
  const ContentUriHelperMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.contentUriHelper;
}

/// All available methods for the VideoHelper platform channel.
enum VideoHelperMethod {
  extractThumbnail("extractThumbnail"),
  getVideoDuration("getVideoDuration"),
  getVideoMetadata("getVideoMetadata"),
  openVideoInViewer("openVideoInViewer"),
  saveVideoToGallery("saveVideoToGallery");

  final String methodName;
  const VideoHelperMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.videoHelper;
}

/// All available methods for the VideoPicker platform channel.
enum VideoPickerMethod {
  pickVideos("pickVideos"),
  pickSingleVideo("pickSingleVideo");

  final String methodName;
  const VideoPickerMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.videoPicker;
}

/// All available methods for the GalleryManager platform channel.
enum GalleryManagerMethod {
  saveVideoToGallery("saveVideoToGallery");

  final String methodName;
  const GalleryManagerMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.galleryManager;
}

/// All available methods for the UploadService platform channel.
enum UploadServiceMethod {
  updateProgress("updateProgress");

  final String methodName;
  const UploadServiceMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.uploadService;
}

/// All available methods for the iOS Background Uploader platform channel.
/// This is iOS-only and handles background URLSession uploads for S3 chunks.
enum IosBackgroundUploaderMethod {
  cancelUpload("cancelUpload");

  final String methodName;
  const IosBackgroundUploaderMethod(this.methodName);

  static PlatformChannels get channel => PlatformChannels.iosBackgroundUploader;
}
