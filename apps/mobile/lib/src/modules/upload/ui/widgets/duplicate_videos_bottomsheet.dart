import "dart:io";

import "package:stera/src/core/common/formatters/format_file_name.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/modules/upload/helpers/upload_utils.dart";
import "package:stera/src/modules/upload/models/duplicate_video_info.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_status_badge.dart";
import "package:stera/src/services/content_uri_service/content_uri_service.dart";
import "package:stera/src/services/video_picker_service/channels/video_metadata_method_channels.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

class DuplicateVideosBottomSheet extends StatefulWidget {
  final List<String> dupUris;
  final VoidCallback onConfirm;

  const DuplicateVideosBottomSheet({
    super.key,
    required this.dupUris,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required List<String> dupUris,
    required VoidCallback onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          DuplicateVideosBottomSheet(dupUris: dupUris, onConfirm: onConfirm),
    );
  }

  @override
  State<DuplicateVideosBottomSheet> createState() =>
      _DuplicateVideosBottomSheetState();
}

class _DuplicateVideosBottomSheetState
    extends State<DuplicateVideosBottomSheet> {
  DuplicateVideoInfo? _videoInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideoInfo();
  }

  Future<void> _loadVideoInfo() async {
    // Only load the first duplicate video
    if (widget.dupUris.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final uriString = widget.dupUris.first;
    final uri = Uri.parse(uriString);
    final isContentUri = uri.scheme == "content";
    final isFileUri = uri.scheme == "file";
    final isAppSupportUri = uri.scheme == "appsupport";
    final isSecurityScopedUri =
        isContentUri || isAppSupportUri || (Platform.isIOS && isFileUri);

    int? fileSize;
    String? fileName;

    try {
      if (isSecurityScopedUri) {
        fileSize = await ContentUriService.getFileSize(uri);
        final fileMetadata = await ContentUriService.getFileMetadata(uri);
        fileName = fileMetadata?["name"];
      } else {
        String filePath = uriString;
        if (uri.scheme == "file") {
          filePath = uri.toFilePath();
        }
        final file = File(filePath);
        if (await file.exists()) {
          fileSize = await file.length();
          fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
        }
      }
    } catch (_) {
      // Ignore errors, we'll show what we can
    }

    // Try to get more metadata from video helper
    final videoMetadata = await VideoMetadataMethodChannels.getVideoMetadata(
      uri,
    );
    final metadataName = videoMetadata?["name"] as String?;
    if (metadataName != null && metadataName.isNotEmpty) {
      fileName = metadataName;
    }

    // Get thumbnail
    final thumbnail = await VideoMetadataMethodChannels.extractThumbnail(uri);

    // Get duration
    final duration = await VideoMetadataMethodChannels.getVideoDuration(uri);

    if (mounted) {
      setState(() {
        _videoInfo = DuplicateVideoInfo(
          uri: uriString,
          fileName: fileName,
          fileSize: fileSize,
          durationMs: duration != null ? duration * 1000 : null,
          thumbnailPath: thumbnail,
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: ShapeDecoration(
        color: colors.surfaceSecondary,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video display in upload file tile style
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CupertinoActivityIndicator(),
                    ),
                  )
                else if (_videoInfo != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 150,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: ShapeDecoration(
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          color: colors.neutralLightGray,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Thumbnail
                            SizedBox(
                              height: 100,
                              child: _buildVideoThumbnail(_videoInfo!, context),
                            ),
                            // File info
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    truncateFileName(
                                      _videoInfo!.displayName,
                                      25,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: textTheme.bodyXs.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  UploadFileTileStatusBadge(
                                    filesize: _videoInfo!.fileSize,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),

                if (!_isLoading && _videoInfo != null) ...[
                  const SizedBox(height: AppSpacing.xl),

                  // Title
                  Text(
                    "Oops! This is a duplicate Video",
                    style: textTheme.headMd.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Description
                  Text(
                    "You have already uploaded this video. Please discard this video and upload a new one.",
                    style: textTheme.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Discard button
                  AppButton(
                    text: "Discard Video",
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onConfirm();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(
    DuplicateVideoInfo videoInfo,
    BuildContext context,
  ) {
    if (videoInfo.thumbnailPath != null) {
      return VideoThumbnail(
        filePath: videoInfo.thumbnailPath,
        durationMs: videoInfo.durationMs,
        width: double.infinity,
        height: 100,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: ShapeDecoration(
            color: context.colors.neutralWhite,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.sm)),
            ),
          ),
          child: Center(
            child: Icon(
              Icons.videocam,
              color: context.colors.textSecondary,
              size: 32,
            ),
          ),
        ),
        if (videoInfo.durationMs != null)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
              decoration: ShapeDecoration(
                color: context.colors.neutralWhite.withValues(alpha: 0.7),
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(AppRadii.xs)),
                ),
              ),
              child: Text(
                formatDuration(videoInfo.durationMs!),
                style: context.textTheme.bodyXs.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
