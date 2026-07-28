import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

enum ButtonSizes { sm, md, lg }

extension ButtonSizesX on ButtonSizes {
  EdgeInsets padding(BuildContext context) {
    switch (this) {
      case ButtonSizes.sm:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm);
      case ButtonSizes.md:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md);
      case ButtonSizes.lg:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg);
    }
  }

  TextStyle text(BuildContext context) {
    switch (this) {
      case ButtonSizes.sm:
        return context.textTheme.bodySmMedium;
      case ButtonSizes.md:
        return context.textTheme.bodyMdMedium;
      case ButtonSizes.lg:
        return context.textTheme.bodyMdMedium;
    }
  }
}
