import "package:stera/src/core/common/utils/app_url_launcher.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/widgets/app_header.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/profile/ui/widgets/account_settings_card.dart";
import "package:stera/src/modules/profile/ui/widgets/local_settings_body.dart";
import "package:stera/src/modules/profile/ui/widgets/profile_footer.dart";
import "package:stera/src/modules/keep_awake/ui/widgets/keep_awake_profile_toggle.dart";
import "package:stera/src/modules/profile/ui/widgets/profile_options_item.dart";
import "package:stera/src/modules/profile/ui/widgets/theme_mode_bottom_sheet.dart";
import "package:stera/src/modules/profile/ui/widgets/user_card.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class ProfilePage extends StatefulWidget {
  static const String routeName = "/profile";

  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ValueNotifier<bool> _logoutLoadingNotifier = ValueNotifier<bool>(false);

  // static const Set<UploadStatus> _unfinishedUploadStatuses = {
  //   UploadStatus.notStarted,
  //   UploadStatus.pending,
  //   UploadStatus.uploading,
  //   UploadStatus.failed,
  // };

  @override
  void dispose() {
    _logoutLoadingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: context.w,
        height: context.h,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              context.colors.surfacePrimary,
              BlendMode.modulate,
            ),
          ),
        ),
        child: SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppHeader(
              text1: AppConfig.noAuthMode ? "Settings" : "Profile",
              text2: "",
            ),
            // An auth-free build has no account to show or delete, so the body
            // splits rather than the page forking — the authed tree below is
            // untouched.
            body: AppConfig.noAuthMode
                ? const LocalSettingsBody()
                : _profileBody(context),
          ),
        ),
      ),
    );
  }

  Widget _profileBody(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UserCard(),
          const SizedBox(height: AppSpacing.lg),
          const SizedBox(height: AppSpacing.lg),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              color: context.colors.surfaceSecondary,
            ),
            child: Column(
              children: [
                ProfileOptionsItem(
                  title: "Appearance",
                  subtitle: "Light, dark, or match your device settings",
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => const ThemeModeBottomSheet(),
                    );
                  },
                ),
                Divider(color: context.colors.neutralLightGray),
                const KeepAwakeProfileToggle(),
                Divider(color: context.colors.neutralLightGray),
                ProfileOptionsItem(
                  title: "Join Discord",
                  subtitle: "Connect with our community for support",
                  onTap: () {
                    AppUrlLauncher.launchUrl(AppConstants.discordInvite);
                  },
                ),
                Divider(color: context.colors.neutralLightGray),
                ProfileOptionsItem(
                  title: "Contact Us",
                  subtitle: "Reach out to our team for help",
                  onTap: () {
                    final userId = context.read<AuthProvider>().user?.id;
                    AppUrlLauncher.launchEmail(
                      context: context,
                      subject: "Contact Us",
                      body: userId != null ? "\n\n---\nUser ID: $userId" : null,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const AccountSettingsCard(),
          const SizedBox(height: AppSpacing.lg),
          const ProfileFooter(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
