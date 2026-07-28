import "package:flutter/services.dart";

enum PlatformChannels {
  contentUriHelper("content_uri_helper"),
  videoHelper("video_helper"),
  videoPicker("custom_document_picker"),
  galleryManager("gallery_manager"),
  uploadService("upload_service"),
  iosBackgroundUploader("ios_background_uploader");

  final String channelName;
  const PlatformChannels(this.channelName);

  MethodChannel get channel => MethodChannel(channelName);
}
