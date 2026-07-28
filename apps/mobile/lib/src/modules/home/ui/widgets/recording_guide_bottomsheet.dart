import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";

/// The whole recording workflow, start to finish, as one scrollable timeline.
///
/// This used to be a four-page carousel. A guide is something people scan and
/// re-scan — "what was the transfer step again?" — and a pager hides three
/// quarters of it behind a Next button, with no way to see how much is left.
/// Laid out as a rail, every step is visible, skimmable and linkable to the
/// one before it.
class RecordingGuideBottomSheet extends StatelessWidget {
  const RecordingGuideBottomSheet({super.key});

  static const List<_GuideStepData> _steps = [
    _GuideStepData(
      icon: SolarIconsOutline.cameraMinimalistic,
      title: "Set up your shot",
      description:
          "Frame the scene so the interaction is clear and easy to review later.",
      bullets: [
        "Record in landscape, never portrait.",
        "Keep both hands and the target object in frame.",
        "Use steady, well-lit, unobstructed shots.",
        "Avoid talking during the recording.",
      ],
    ),
    _GuideStepData(
      icon: SolarIconsOutline.videocameraRecord,
      title: "Record the session",
      description:
          "Capture the full task end-to-end on your device or headset.",
      bullets: [
        "Start recording before you begin the task.",
        "Complete the task without cutting the clip.",
        "Stop recording after the interaction is done.",
        "Focus on the hand-object interaction throughout.",
      ],
    ),
    _GuideStepData(
      icon: SolarIconsOutline.laptopMinimalistic,
      title: "Transfer files to your Mac",
      description:
          "Move the recording from your device to a local folder you can access.",
      bullets: [
        "Connect the device to your Mac with a USB-C cable.",
        "Trust the computer when prompted on the device.",
        "Use Finder or Image Capture to copy the clip over.",
        "Save it somewhere easy to find, like Desktop or Downloads.",
      ],
    ),
    _GuideStepData(
      icon: SolarIconsOutline.cloudUpload,
      title: "Upload in Stera",
      description:
          "Send the transferred clip to the cloud from the app when you're ready.",
      bullets: [
        "Open Stera and tap the + on the bottom bar.",
        "Pick the file(s) you copied over from your Mac.",
        "Submit on a stable internet connection.",
        "Uploads require an organization-linked account.",
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad =
        AppSpacing.lgPlus + MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: context.colors.surfaceSecondary,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.lgPlus),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.h * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lgPlus,
                AppSpacing.xl,
                AppSpacing.lgPlus,
                AppSpacing.lg,
              ),
              child: SheetHeader(
                title: "Recording guide",
                subtitle:
                    "Four steps from your first recording to an uploaded "
                    "dataset.",
                onClose: () => AppRouter.pop(),
              ),
            ),
            // Only the timeline scrolls, so the header stays put and the
            // button stays reachable however long the guide gets.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lgPlus,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _GuideStep(
                        data: _steps[i],
                        stepNumber: i + 1,
                        isLast: i == _steps.length - 1,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lgPlus,
                AppSpacing.lg,
                AppSpacing.lgPlus,
                bottomPad,
              ),
              child: const AppButton(text: "Got it", onPressed: AppRouter.pop),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStepData {
  const _GuideStepData({
    required this.icon,
    required this.title,
    required this.description,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> bullets;
}

/// One step on the rail: a numbered marker in the gutter, the step's content
/// to its right, and a connecting line down to the next step.
class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.data,
    required this.stepNumber,
    required this.isLast,
  });

  final _GuideStepData data;
  final int stepNumber;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepMarker(stepNumber: stepNumber, isLast: isLast),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              // The last step needs no trailing gap — the button follows it.
              padding: EdgeInsets.only(
                bottom: isLast ? AppSpacing.none : AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.title,
                          style: context.textTheme.headSm.copyWith(
                            color: context.colors.textPrimary,
                            fontWeight: AppType.semibold,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        data.icon,
                        size: AppSpacing.lgPlus,
                        color: context.colors.textTertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    data.description,
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: ShapeDecoration(
                      color: context.colors.surfaceTertiary,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < data.bullets.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.sm),
                          _GuideBulletLine(text: data.bullets[i]),
                        ],
                      ],
                    ),
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

class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.stepNumber, required this.isLast});

  final int stepNumber;
  final bool isLast;

  static const double _diameter = AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _diameter,
      child: Column(
        children: [
          Container(
            width: _diameter,
            height: _diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.neutralBlack,
            ),
            child: Text(
              "$stepNumber",
              style: context.textTheme.bodyXsMedium.copyWith(
                color: context.colors.neutralWhite,
              ),
            ),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: AppSpacing.xxs,
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                decoration: ShapeDecoration(
                  color: context.colors.borderDivider,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideBulletLine extends StatelessWidget {
  const _GuideBulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Icon(
            SolarIconsOutline.checkCircle,
            size: AppSpacing.lg,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: context.textTheme.bodySm.copyWith(
              color: context.colors.textPrimary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
