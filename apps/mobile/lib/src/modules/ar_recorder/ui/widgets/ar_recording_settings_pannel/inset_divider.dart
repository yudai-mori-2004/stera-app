import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        thickness: 1,
        color: context.colors.borderDivider,
      ),
    );
  }
}
