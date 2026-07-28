import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_header_action_button.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/modules/profile/ui/profile_page.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String text1;
  final String text2;
  final TextStyle? customStyle1;
  final TextStyle? customStyle2;
  final bool showProfileButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  const AppHeader({
    super.key,
    required this.text1,
    required this.text2,
    this.customStyle1,
    this.customStyle2,
    this.showProfileButton = true,
    this.onBackPressed,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final isProfilePage = state.matchedLocation.contains("/profile");
    // The title sits flush against the back button when there is one, and at
    // the default inset when there isn't. Read the same signal [AppBar] uses
    // to decide whether to draw that button: anything else (route.isCurrent,
    // say) also flips while a bottom sheet is open, and the title visibly
    // slides sideways under the sheet.
    final showsBackButton =
        ModalRoute.of(context)?.impliesAppBarDismissal ?? false;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: kToolbarHeight,
      automaticallyImplyLeading: true,
      centerTitle: false,
      titleSpacing: showsBackButton ? 0 : 16,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text1,
              style:
                  customStyle1 ??
                  context.textTheme.head4XlGaramond.copyWith(
                    fontWeight: AppType.bold,
                    fontSize: AppType.xl3Plus,
                  ),
            ),
            TextSpan(
              text: text2,
              style:
                  customStyle2 ??
                  context.textTheme.head4XlGaramond.copyWith(
                    fontWeight: AppType.bold,
                    fontStyle: FontStyle.italic,
                    fontSize: AppType.xl3Plus,
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        ...?actions,

        // Same destination in both builds — only the glyph moves. There is no
        // account behind it in an auth-free build, so a person icon would be
        // promising something the page doesn't have.
        if (showProfileButton && !isProfilePage)
          AppHeaderActionButton(
            icon: AppConfig.noAuthMode ? Icons.settings_outlined : Icons.person,
            semanticLabel: AppConfig.noAuthMode ? "Settings" : "Profile",
            endPadding: 16,
            onTap: () => AppRouter.push(ProfilePage.routeName),
          ),
      ],
    );
  }
}
