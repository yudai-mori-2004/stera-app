import "package:flutter/cupertino.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";

/// Centered activity indicator with an optional caption, shown while an
/// MCAP file or topic is being read.
class McapLoadingState extends StatelessWidget {
  final String? message;

  const McapLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(color: context.colors.textPrimary),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
