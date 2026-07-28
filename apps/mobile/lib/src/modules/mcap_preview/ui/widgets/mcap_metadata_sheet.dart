import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";

/// Bottom sheet showing one MCAP metadata record as selectable key/value
/// text. Open it with [show].
class McapMetadataSheet extends StatelessWidget {
  final String title;
  final Map<String, String> entries;

  const McapMetadataSheet({
    super.key,
    required this.title,
    required this.entries,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Map<String, String> entries,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceSecondary,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lgPlus)),
      ),
      builder: (_) => McapMetadataSheet(title: title, entries: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.h * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.lgPlus, AppSpacing.lgPlus, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(
                title: title,
                subtitle:
                    "${entries.length} "
                    "entr${entries.length == 1 ? "y" : "ies"} • "
                    "long-press to copy",
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: ShapeDecoration(
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    color: context.colors.surfacePrimary,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      entries.entries
                          .map((e) => "${e.key}:\n${e.value}")
                          .join("\n\n"),
                      style: context.textTheme.bodyXsMono.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
