import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/svg.dart";

/// Builds the leading visual for a tile. Supports a plain [Icon] or an SVG
/// asset ([iconPath]); [none] renders nothing.
extension Leading on InteractiveListTileIconState {
  Widget buildLeading({IconData? icon, String? iconPath, double? iconSize}) {
    switch (this) {
      case InteractiveListTileIconState.normal:
        return iconPath != null
            ? SvgPicture.asset(
                iconPath,
                width: iconSize ?? 24,
                height: iconSize ?? 24,
              )
            : Icon(icon, size: iconSize ?? 24);
      case InteractiveListTileIconState.none:
        return const SizedBox.shrink();
    }
  }
}
