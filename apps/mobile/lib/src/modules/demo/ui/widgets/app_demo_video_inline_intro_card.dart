import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_card.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/demo/constants/app_demo_video.dart";
import "package:stera/src/modules/demo/ui/demo_video_fullscreen_page.dart";
import "package:stera/src/modules/demo/ui/widgets/demo_video_inline_preview.dart";
import "package:stera/src/modules/home/ui/widgets/recording_guide_bottomsheet.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:solar_icons/solar_icons.dart";

/// Home / capture intro card: inline demo playback when [AppDemoVideo] is
/// configured, otherwise the still thumbnail so the section keeps its shape.
class AppDemoVideoInlineIntroCard extends StatelessWidget {
  const AppDemoVideoInlineIntroCard({super.key});

  static const double _previewAspectRatio = 16 / 9;

  void _incrementPlayCount() {
    final n =
        KvStore.get<int>(KvStoreKeys.homeDemoVideoPlayCount, defaultValue: 0) ??
        0;
    KvStore.set(KvStoreKeys.homeDemoVideoPlayCount, n + 1);
  }

  void _openGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const RecordingGuideBottomSheet(),
    );
  }

  Widget _thumbnailOnly() {
    return AspectRatio(
      aspectRatio: _previewAspectRatio,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Image.asset(
          AppAssets.appVidDemoThumbnail,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  Widget _videoPreview(BuildContext context) {
    final playCount =
        KvStore.get<int>(KvStoreKeys.homeDemoVideoPlayCount, defaultValue: 0) ??
        0;

    return DemoVideoInlinePreview(
      aspectRatio: _previewAspectRatio,
      outerClipRadius: AppRadii.md,
      autoplayOnInit: playCount == 0,
      onPlayingBegan: _incrementPlayCount,
      onFirstUserInteraction: _incrementPlayCount,
      onOpenFullscreen: () => context.push(DemoVideoFullscreenPage.routeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: "Collect Multimodal data",
            subtitle:
                "Collect raw footage and get 6dof poses, depth, and action labels",
            maxSubtitleLines: 2,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (AppDemoVideo.isConfigured)
            _videoPreview(context)
          else
            _thumbnailOnly(),
          // The guide sits inside this card rather than in one of its own: the
          // next step after watching the demo, not a separate topic.
          const SizedBox(height: AppSpacing.lg),
          Pressable(
            behavior: HitTestBehavior.opaque,
            semanticLabel: "Open the step-by-step recording guide",
            onTap: () => _openGuide(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: ShapeDecoration(
                color: context.colors.neutralLightGray,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              child: Row(
                spacing: AppSpacing.sm,
                children: [
                  Icon(
                    SolarIconsOutline.bookMinimalistic,
                    color: context.colors.textPrimary,
                    size: AppSpacing.lg,
                  ),
                  const Expanded(
                    child: SectionHeader(
                      title: "Step-by-step guide",
                      subtitle: "Record, transfer to your Mac, upload",
                    ),
                  ),
                  Icon(
                    SolarIconsOutline.arrowRight,
                    color: context.colors.textPrimary,
                    size: AppSpacing.lg,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
