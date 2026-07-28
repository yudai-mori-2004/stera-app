import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:flutter/material.dart";

/// Resolves a tile's fill from its [InteractiveListTileType] + interaction
/// [InteractiveListTileState]. Tiles are transparent by default so they read
/// against the [InteractiveList] container; only hover paints a subtle fill.
extension InteractiveListTileBackgroundColor on InteractiveListTileType {
  Color backgroundColor(BuildContext context, InteractiveListTileState state) {
    if (this == InteractiveListTileType.info) {
      return Colors.transparent;
    }
    switch (state) {
      case InteractiveListTileState.normal:
        return Colors.transparent;
      case InteractiveListTileState.hover:
        return context.colors.surfaceTertiary;
      case InteractiveListTileState.disabled:
        return Colors.transparent;
    }
  }
}
