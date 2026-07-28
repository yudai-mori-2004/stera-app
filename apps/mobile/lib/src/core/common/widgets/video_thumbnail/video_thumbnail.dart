import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/utils/network_image_url.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";

enum ThumbnailSource { network, file }

class VideoThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String? filePath;
  final int? durationMs;
  final double width;
  final double height;
  final bool showDuration;
  final Widget? overlay;

  const VideoThumbnail({
    super.key,
    this.imageUrl,
    this.filePath,
    this.durationMs,
    this.width = double.infinity,
    this.height = 112,
    this.showDuration = true,
    this.overlay,
  });

  static final Map<String, Uint8List> _decodedBytesCache = {};

  static void clearCache() => _decodedBytesCache.clear();

  Uint8List? _tryDecodeBase64(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final key = value.trim();
    final cached = _decodedBytesCache[key];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(key);
      if (bytes.length < 8) return null;
      if (!_hasImageMagic(bytes)) return null;
      _decodedBytesCache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  bool _hasImageMagic(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return true;
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return true;
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x38 &&
        (b[4] == 0x37 || b[4] == 0x39) &&
        b[5] == 0x61) {
      return true;
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    return false;
  }

  Widget _buildThumbnailImage(BuildContext context) {
    final fallback = Center(
      child: Icon(
        Icons.videocam,
        color: context.colors.textSecondary,
        size: 32,
      ),
    );

    // Decode thumbnails at display size rather than full camera resolution.
    // Constrain exactly one axis (prefer height) so the aspect ratio is
    // preserved and BoxFit.cover still crops correctly — this bounds the
    // decoded bitmap to a few KB instead of multi-MB per tile, which is the
    // difference between a few MB and hundreds of MB of image cache across a
    // scrolling recordings list.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? cacheW;
    int? cacheH;
    if (height.isFinite) {
      cacheH = (height * dpr).round();
    } else if (width.isFinite) {
      cacheW = (width * dpr).round();
    }

    if (isValidHttpImageUrl(imageUrl)) {
      return CachedNetworkImage(
        imageUrl: imageUrl!.trim(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        // Short enough not to feel laggy when scrolling a list of cached
        // thumbnails, long enough that a cold-loaded one doesn't pop in.
        fadeInDuration: const Duration(milliseconds: 200),
        // Zero: the placeholder→image cross-fade double-exposes otherwise.
        fadeOutDuration: Duration.zero,
        errorWidget: (_, _, _) => fallback,
      );
    }

    final base64Bytes = _tryDecodeBase64(imageUrl);
    if (base64Bytes != null) {
      return Image.memory(
        base64Bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    if (filePath != null && filePath!.trim().isNotEmpty) {
      return Image.file(
        File(filePath!.trim()),
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return fallback;
  }

  String get _durationLabel {
    final ms = durationMs;
    if (ms == null) return "--:--";
    return Duration(milliseconds: ms).inSeconds.formatDuration;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        color: context.colors.neutralDarkGray.withValues(alpha: 0.2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: _buildThumbnailImage(context),
          ),
          if (showDuration)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: context.colors.surfacePrimary,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Text(
                  _durationLabel,
                  style: context.textTheme.bodyXs.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ?overlay,
        ],
      ),
    );
  }
}
