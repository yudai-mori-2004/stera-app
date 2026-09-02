import "package:stera/src/core/common/utils/app_url_launcher.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/open_source_badge.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/services/app_info/app_info.dart";
import "package:stera/src/core/config/constants/brand.dart";
import "package:stera/src/core/config/constants/attribution.dart";
import "package:flutter/material.dart";

class ProfileFooter extends StatelessWidget {
  const ProfileFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        spacing: AppSpacing.md,
        children: [
          Row(
            spacing: AppSpacing.sm,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 0.5,
                width: 36,
                color: context.colors.textPrimary,
              ),
              Text("v${AppInfo.displayVersion}"),
              Container(
                height: 0.5,
                width: 36,
                color: context.colors.textPrimary,
              ),
            ],
          ),
          Pressable(
            behavior: HitTestBehavior.opaque,
            semanticLabel: "View ${Brand.appName} source code on GitHub",
            onTap: () => AppUrlLauncher.launchUrl(AppConstants.sourceRepo),
            child: Column(
              spacing: AppSpacing.xsPlus,
              children: [
                const OpenSourceBadge(),
                Text(
                  "${Brand.appName} is open source — view the code on GitHub",
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyXs.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (Attribution.enabled && Attribution.showInProfileFooter)
            Pressable(
              behavior: HitTestBehavior.opaque,
              semanticLabel:
                  "Visit ${Attribution.upstreamName}, the upstream project",
              onTap: () =>
                  AppUrlLauncher.launchUrl(Attribution.upstreamRepo),
              child: Text(
                Attribution.text,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyXs.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
