import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_card.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/keep_awake/ui/widgets/keep_awake_prompt_banner.dart";
import "package:stera/src/modules/home/data/enums/current_page.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload_estimate/helpers/upload_estimate_format.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:provider/provider.dart";

class UploadProgressCard extends StatelessWidget {
  const UploadProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<UploadProvider, _UploadProgressCardUi>(
      selector: (_, up) {
        final progress = up.currentProgress;
        final hasActiveUpload =
            progress != null &&
            !(progress.progress >= 100 &&
                progress.videoIndex >= progress.totalVideos);
        if (!hasActiveUpload) {
          return _UploadProgressCardUi(
            loading: up.loading || up.picker.loading,
            data: null,
          );
        }
        final isPaused = up.queueManager.isPaused;
        return _UploadProgressCardUi(
          loading: up.loading || up.picker.loading,
          data: _ProgressCardData(
            progress: progress.progress,
            videoIndex: progress.videoIndex,
            totalVideos: progress.totalVideos,
            isPaused: isPaused,
            eta: isPaused ? null : up.currentEta,
          ),
        );
      },
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, ui, _) {
        if (ui.data == null) {
          return _buildIdleCard(context, ui.loading);
        }
        return _buildActiveCard(context, ui.data!);
      },
    );
  }

  Widget _buildIdleCard(BuildContext context, bool loading) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: "Currently uploading",
            subtitle: "Nothing uploading right now — record to get started.",
            number: 0,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            text: "Start Recording",
            isLoading: loading,
            onPressed: loading
                ? null
                : () async {
                    final up = context.read<UploadProvider>();
                    final np = context.read<NavigationProvider>();
                    np.setCurrentPage(CurrentPage.addUpload);
                    await up.picker.recordVideosForUpload(
                      context,
                      up.selection,
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCard(BuildContext context, _ProgressCardData data) {
    return AppCard(
      onTap: () {
        context.read<NavigationProvider>().setCurrentPage(CurrentPage.upload);
      },
      child: Column(
        children: [
          SectionHeader(
            title: data.isPaused ? "Uploads paused" : "Uploads in progress",
            subtitle: data.isPaused
                ? "Resume anytime from the Library tab."
                : "Sending your videos to the cloud.",
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const ValueKey("upload_progress"),
            width: double.infinity,
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              color: context.colors.neutralLightGray,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            context.colors.neutralDarkGray.withValues(
                              alpha: 0.2,
                            ),
                            context.colors.neutralDarkGray.withValues(
                              alpha: 0.01,
                            ),
                          ],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.srcIn,
                      child: SvgPicture.asset(
                        AppAssets.wave,
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          context.colors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: data.isPaused
                                  ? context.colors.yellow.withValues(alpha: 0.1)
                                  : context.colors.textPrimary.withValues(
                                      alpha: 0.05,
                                    ),
                              shape: BoxShape.circle,
                            ),
                            child: data.isPaused
                                ? Icon(
                                    Icons.pause_rounded,
                                    size: 16,
                                    color: context.colors.yellow,
                                  )
                                : SvgPicture.asset(
                                    AppAssets.arrowSquareUpIcon,
                                    width: 16,
                                    height: 16,
                                    colorFilter: ColorFilter.mode(
                                      context.colors.textPrimary,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "${data.progress}%",
                                style: context.textTheme.head3Xl.tabular
                                    .copyWith(
                                      color: context.colors.textPrimary,
                                    ),
                              ),
                              if (data.isPaused) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.colors.yellow.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(AppRadii.xsPlus),
                                    ),
                                    child: Text(
                                      "PAUSED",
                                      style: context.textTheme.bodyXs.copyWith(
                                        color: context.colors.yellow,
                                        fontWeight: AppType.semibold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            "${data.videoIndex - 1} of ${data.totalVideos} uploaded",
                            style: context.textTheme.bodySm.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RepaintBoundary(
                        child: ClipRSuperellipse(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: _AnimatedProgressBar(
                            progress: data.progress / 100.0,
                            isPaused: data.isPaused,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (data.eta != null)
                            Text(
                              formatEtaShort(data.eta!),
                              style: context.textTheme.bodySm.copyWith(
                                color: context.colors.textTertiary,
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                data.isPaused
                                    ? "Tap to resume"
                                    : "Tap to see details",
                                style: context.textTheme.bodySm.copyWith(
                                  color: context.colors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.chevron_right,
                                color: context.colors.textTertiary,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!data.isPaused) ...[
            const SizedBox(height: AppSpacing.smPlus),
            const KeepAwakePromptBanner(
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

@immutable
class _UploadProgressCardUi {
  const _UploadProgressCardUi({required this.loading, required this.data});

  final bool loading;
  final _ProgressCardData? data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UploadProgressCardUi &&
          runtimeType == other.runtimeType &&
          loading == other.loading &&
          data == other.data;

  @override
  int get hashCode => Object.hash(loading, data);
}

class _AnimatedProgressBar extends StatefulWidget {
  const _AnimatedProgressBar({required this.progress, required this.isPaused});

  final double progress;
  final bool isPaused;

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.progress;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: _currentValue,
      end: _currentValue,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(
        begin: _currentValue,
        end: widget.progress,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0).then((_) {
        _currentValue = widget.progress;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return LinearProgressIndicator(
          value: _animation.value,
          minHeight: 8,
          backgroundColor: context.colors.textPrimary.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.isPaused
                ? context.colors.yellow
                : context.colors.textPrimary,
          ),
        );
      },
    );
  }
}

@immutable
class _ProgressCardData {
  const _ProgressCardData({
    required this.progress,
    required this.videoIndex,
    required this.totalVideos,
    required this.isPaused,
    this.eta,
  });

  final int progress;
  final int videoIndex;
  final int totalVideos;
  final bool isPaused;

  /// Live time-remaining estimate for the upload in flight; null while
  /// paused or before a speed is known.
  final Duration? eta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ProgressCardData &&
          runtimeType == other.runtimeType &&
          progress == other.progress &&
          videoIndex == other.videoIndex &&
          totalVideos == other.totalVideos &&
          isPaused == other.isPaused &&
          eta == other.eta;

  @override
  int get hashCode =>
      Object.hash(progress, videoIndex, totalVideos, isPaused, eta);
}
