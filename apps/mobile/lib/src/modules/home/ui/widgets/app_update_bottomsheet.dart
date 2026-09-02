import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/common/utils/app_url_launcher.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/startup/ui/startup_view.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/core/config/constants/brand.dart";
import "package:flutter/material.dart";

class AppUpdateBottomSheet extends StatelessWidget {
  const AppUpdateBottomSheet({
    super.key,
    required this.isMajorUpdate,
    required this.version,
    required this.description,
    required this.appStoreLink,
  });

  final bool isMajorUpdate;
  final String? version;
  final String description;
  final String appStoreLink;

  @override
  Widget build(BuildContext context) {
    final bottomPad = 20 + MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: context.colors.surfacePrimary,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lgPlus)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.sm, AppSpacing.lgPlus, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lgPlus),
              SheetHeader(
                title: isMajorUpdate ? "Update required" : "Update available",
                subtitle: isMajorUpdate
                    ? "A required update is ready to install."
                    : "A new version of ${Brand.appName} is ready to install.",
                onClose: isMajorUpdate ? null : () => AppRouter.pop(),
              ),
              const SizedBox(height: AppSpacing.lgPlus),
              _UpdateCard(
                description: description,
                version: version,
                isMajorUpdate: isMajorUpdate,
              ),
              const SizedBox(height: AppSpacing.lgPlus),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: Row(
                  children: [
                    if (!isMajorUpdate) ...[
                      Expanded(
                        flex: 1,
                        child: AppButton(
                          text: "Later",
                          type: ButtonType.secondary,
                          showShadow: false,
                          onPressed: () => AppRouter.pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      flex: 1,
                      child: AppButton(
                        text: "Update now",
                        showShadow: false,
                        onPressed: () async {
                          await AppUrlLauncher.launchUrl(appStoreLink);
                          StartupView.restart();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.description,
    required this.version,
    required this.isMajorUpdate,
  });

  final String description;
  final String? version;
  final bool isMajorUpdate;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.mdPlus)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lgPlus),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              AppAssets.update(Theme.of(context).brightness),
              width: context.w * 0.5,
              height: context.w * 0.5,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AppSpacing.lgPlus),
            if (version != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceTertiary,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  border: Border.all(color: context.colors.borderDivider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isMajorUpdate
                            ? context.colors.textAlert
                            : context.colors.green,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xsPlus),
                    Text(
                      "v$version",
                      style: context.textTheme.bodyXs.copyWith(
                        color: context.colors.textSecondary,
                        fontWeight: AppType.semibold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              description,
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textPrimary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
