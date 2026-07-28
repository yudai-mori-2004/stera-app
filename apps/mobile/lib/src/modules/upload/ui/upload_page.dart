import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_header.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/keep_awake/ui/widgets/keep_awake_header_action.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/sections/currently_uploading_options_section.dart";
import "package:stera/src/modules/upload/ui/sections/failed_upload_section.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_empty_state.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/modules/uploaded_videos/ui/widgets/uploaded_videos_grid.dart";
import "package:stera/src/modules/uploaded_videos/ui/widgets/uploaded_videos_header.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UploadPage extends StatelessWidget {
  static const String routeName = "/upload";
  const UploadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      height: context.h,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(AppAssets.texture),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            context.colors.surfacePrimary,
            BlendMode.modulate,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AppHeader(
          text1: "Library",
          text2: "",
          actions: [KeepAwakeHeaderAction()],
        ),
        body: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Selector<UploadProvider, _UploadPageData>(
                selector: (_, up) {
                  final uploads = up.uploadsMap.values;
                  final hasActiveUploads = uploads.any(
                    (u) =>
                        u.status == UploadStatus.pending ||
                        u.status == UploadStatus.uploading ||
                        u.status == UploadStatus.paused ||
                        u.status == UploadStatus.failed,
                  );
                  return _UploadPageData(
                    hasActiveUploads: hasActiveUploads,
                    isPaused: up.queueManager.isPaused,
                    isCancelling: up.queueManager.isCancelling,
                  );
                },
                builder: (context, data, _) {
                  if (!data.hasActiveUploads) {
                    return const UploadEmptyState();
                  }

                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        width: context.w,
                        decoration: ShapeDecoration(
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(AppRadii.lg),
                          ),
                          color: context.colors.surfaceSecondary,
                        ),
                        child: const Column(
                          children: [
                            CurrentlyUploadingSection(),
                            SizedBox(height: AppSpacing.sm),
                            FailedUploadSection(),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: context.w,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                padding: const EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.lg, AppSpacing.lgPlus, AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.lgPlus),
                  color: context.colors.surfaceSecondary.withValues(
                    alpha: 0.88,
                  ),
                  border: Border.all(
                    color: context.colors.neutralLightGray.withValues(
                      alpha: 0.18,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.neutralBlack.withValues(alpha: 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.colors.surfaceSecondary.withValues(alpha: 0.95),
                      context.colors.surfaceSecondary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "// ALL UPLOADS",
                      style: context.textTheme.bodySm.copyWith(
                        color: context.colors.textSecondary.withValues(
                          alpha: 0.78,
                        ),
                        letterSpacing: 1.2,
                        fontWeight: AppType.semibold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xsPlus),
                    const UploadedVideosHeader(),
                    Consumer<UploadedVideosProvider>(
                      builder: (_, upv, _) {
                        if (upv.loading) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Center(
                              child: CupertinoActivityIndicator(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          );
                        }

                        return const UploadedVideosGrid(expand: false);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _UploadPageData {
  const _UploadPageData({
    required this.hasActiveUploads,
    required this.isPaused,
    required this.isCancelling,
  });

  final bool hasActiveUploads;
  final bool isPaused;
  final bool isCancelling;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UploadPageData &&
          runtimeType == other.runtimeType &&
          hasActiveUploads == other.hasActiveUploads &&
          isPaused == other.isPaused &&
          isCancelling == other.isCancelling;

  @override
  int get hashCode => Object.hash(hasActiveUploads, isPaused, isCancelling);
}
