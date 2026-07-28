import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_type.dart";

/// Mirrors [AppHeader]'s Garamond two-part title without its
/// `GoRouterState.of` coupling, so it can live in raw-`Navigator` routes
/// (the preview pages are pushed like `ProcessingPage`, outside go_router).
class McapPreviewHeader extends StatelessWidget implements PreferredSizeWidget {
  final String text1;
  final String text2;
  final double fontSize;
  final bool implyLeading;
  final List<Widget>? actions;

  const McapPreviewHeader({
    super.key,
    required this.text1,
    required this.text2,
    this.fontSize = AppType.xl3Plus,
    this.implyLeading = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: kToolbarHeight,
      automaticallyImplyLeading: implyLeading,
      centerTitle: false,
      titleSpacing: implyLeading ? 0 : 16,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text1,
              style: context.textTheme.head4XlGaramond.copyWith(
                fontWeight: AppType.bold,
                fontSize: fontSize,
              ),
            ),
            TextSpan(
              text: text2,
              style: context.textTheme.head4XlGaramond.copyWith(
                fontWeight: AppType.bold,
                fontStyle: FontStyle.italic,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: actions,
    );
  }
}
