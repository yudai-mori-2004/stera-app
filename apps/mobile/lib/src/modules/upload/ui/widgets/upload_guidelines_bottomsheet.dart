import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list_tile.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class UploadGuidelinesCard extends StatelessWidget {
  const UploadGuidelinesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Before you record", style: context.textTheme.headMd),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Please read our recording guidelines before you record the videos.",
                style: context.textTheme.bodySm.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        OutlinedButton(
          onPressed: () => showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            useSafeArea: true,
            enableDrag: true,
            builder: (context) => const UploadGuidelinesBottomSheet(),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xsPlus),
            side: BorderSide(color: context.colors.borderDefault, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text("View", style: context.textTheme.bodySm),
        ),
      ],
    );
  }
}

class UploadGuidelinesBottomSheet extends StatelessWidget {
  const UploadGuidelinesBottomSheet({super.key, this.onGotItPressed});

  final VoidCallback? onGotItPressed;

  static const List<String> generalGuidelines = [
    "Ensure both hands are clearly visible in the frame.",
    "Focus the recording on hand-object interactions.",
    "Maintain a clear, steady, and well-lit video at all times.",
    "Record videos in landscape mode (not portrait).",
    "Finish and submit only fully completed tasks.",
    "Only upload videos you are comfortable sharing publicly.",
  ];

  static const List<String> technicalSpecs = [
    "Upload videos when you have a stable internet connection.",
    "Ensure your device has sufficient available storage before recording.",
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = 20 + MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: context.colors.surfaceSecondary,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lgPlus)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.h * 0.75),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.sm, AppSpacing.lgPlus, bottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lgPlus),
                SheetHeader(
                  title: "Upload guidelines",
                  subtitle:
                      "Read these before you record so your clips meet the "
                      "upload bar.",
                  onClose: () => AppRouter.pop(),
                ),
                const SizedBox(height: AppSpacing.lgPlus),
                const InteractiveListTile(
                  content: _GuidelineBulletList(items: generalGuidelines),
                ),
                const SizedBox(height: AppSpacing.lg),
                const InteractiveListTile(
                  content: _GuidelineBulletList(items: technicalSpecs),
                ),
                const SizedBox(height: AppSpacing.lgPlus),
                AppButton(
                  text: "Start Recording",
                  onPressed: () {
                    onGotItPressed?.call();
                    AppRouter.pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One settings-style card: only bullet lines, no subheading.
class _GuidelineBulletList extends StatelessWidget {
  const _GuidelineBulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.smPlus),
            _GuidelineBulletLine(text: items[i]),
          ],
        ],
      ),
    );
  }
}

/// Same dot + line pattern as [RecordingGuideBottomSheet]’s step bullets.
class _GuidelineBulletLine extends StatelessWidget {
  const _GuidelineBulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: AppSpacing.xsPlus),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.smPlus),
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
