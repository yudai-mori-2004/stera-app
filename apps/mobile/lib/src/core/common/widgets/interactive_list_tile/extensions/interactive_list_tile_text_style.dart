import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:flutter/material.dart";

/// Maps tile content styles onto this app's text theme: titles use [headMd]
/// (the same weight as the settings rows), subtitles use [bodySm] in the
/// secondary tone. Informational tiles can shrink their title to [headSm].
extension InteractiveListTileTextStyle on InteractiveListTileType {
  TextStyle titleTextStyle(BuildContext context, bool isTitleSmall) {
    switch (this) {
      case InteractiveListTileType.normal:
        return context.textTheme.headMd.copyWith(
          color: context.colors.textPrimary,
        );
      case InteractiveListTileType.info:
      case InteractiveListTileType.bulletedInfo:
        return isTitleSmall
            ? context.textTheme.headSm.copyWith(
                color: context.colors.textTertiary,
              )
            : context.textTheme.headMd.copyWith(
                color: context.colors.textPrimary,
              );
    }
  }

  TextStyle subTitleTextStyle(BuildContext context, bool isTitleSmall) {
    switch (this) {
      case InteractiveListTileType.normal:
        return context.textTheme.bodySm.copyWith(
          color: context.colors.textSecondary,
          height: 1.35,
        );
      case InteractiveListTileType.info:
      case InteractiveListTileType.bulletedInfo:
        return isTitleSmall
            ? context.textTheme.bodyMdMedium.copyWith(
                color: context.colors.textPrimary,
              )
            : context.textTheme.bodySm.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              );
    }
  }
}
