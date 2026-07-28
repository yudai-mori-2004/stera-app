import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/formatters/format_bytes.dart";
import "package:stera/src/core/common/utils/app_url_launcher.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_card.dart";
import "package:stera/src/core/common/widgets/info_row/info_row.dart";
import "package:stera/src/core/common/widgets/no_auth_mode_badge.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/ar_recording_settings_panel.dart";
import "package:stera/src/modules/keep_awake/ui/widgets/keep_awake_profile_toggle.dart";
import "package:stera/src/modules/profile/ui/widgets/profile_footer.dart";
import "package:stera/src/modules/profile/ui/widgets/profile_options_item.dart";
import "package:stera/src/modules/profile/ui/widgets/theme_mode_bottom_sheet.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";

/// The settings screen for a `NO_AUTH_MODE` build: everything on the profile
/// page that isn't tied to an account.
///
/// Dropped from the authed version: the user card, the account-settings card
/// (logout and delete-account), and "Contact Us" — the last because its only
/// payload was the Better Auth user id, and reading `AuthProvider` here would
/// throw in a build that doesn't register it.
///
/// Added: recorder settings (otherwise only reachable from the capture header)
/// and an on-device storage summary, which is the closest thing to an upload
/// receipt when there are no uploads.
class LocalSettingsBody extends StatefulWidget {
  const LocalSettingsBody({super.key});

  @override
  State<LocalSettingsBody> createState() => _LocalSettingsBodyState();
}

class _LocalSettingsBodyState extends State<LocalSettingsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Deep-linking straight here (rather than arriving from the capture page)
      // would otherwise show an empty storage summary.
      final provider = context.read<RecordingsProvider>();
      if (provider.sessions.isEmpty && !provider.isLoading) {
        provider.loadSessions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recordings = context.watch<RecordingsProvider>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSpacing.gapLg,
          const Padding(
            padding: AppSpacing.screen,
            child: NoAuthModeBadge(),
          ),
          AppSpacing.gapLg,
          Container(
            margin: AppSpacing.screen,
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
                  title: "Recording settings",
                  subtitle: "Resolution, data streams, IMU and voice commands",
                  onTap: () => ArRecordingSettingsPanel.show(context),
                ),
                Divider(color: context.colors.neutralLightGray),
                ProfileOptionsItem(
                  title: "Join Discord",
                  subtitle: "Connect with our community for support",
                  onTap: () {
                    AppUrlLauncher.launchUrl(AppConstants.discordInvite);
                  },
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
          AppCard(
            margin: AppSpacing.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: "On this device",
                  subtitle: "Recordings are stored in ar_sessions/",
                  maxSubtitleLines: 2,
                ),
                InfoRow(
                  icon: Icons.sd_storage_outlined,
                  label: "Storage used",
                  value: formatBytes(recordings.totalStorageUsedBytes),
                ),
                InfoRow(
                  icon: Icons.folder_outlined,
                  label: "Recordings",
                  value: "${recordings.sessions.length}",
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
          const ProfileFooter(),
          AppSpacing.gapXl,
        ],
      ),
    );
  }
}
