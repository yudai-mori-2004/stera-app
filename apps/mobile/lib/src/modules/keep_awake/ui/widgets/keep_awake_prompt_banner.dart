import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toggle_switch.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/modules/keep_awake/helpers/keep_awake_controller.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// Inline control shown while uploads are active. Uploads always keep running,
/// but they finish faster while the app is open — so this lets the user keep
/// the screen awake without leaving for a separate screen.
class KeepAwakePromptBanner extends StatelessWidget {
  const KeepAwakePromptBanner({
    super.key,
    this.compact = false,
  });

  final bool compact;

  void _toggle(bool on) {
    KeepAwakeController.setEnabled(on);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: KeepAwakeController.enabled,
      builder: (context, on, _) {
        return compact ? _buildCompact(context, on) : _buildFull(context, on);
      },
    );
  }

  Widget _buildCompact(BuildContext context, bool on) {
    return Pressable(
      onTap: () => _toggle(!on),
      pressedScale: 0.97,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(
            on ? Icons.brightness_high_rounded : Icons.brightness_low_outlined,
            size: 14,
            color: on ? context.colors.green : context.colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xsPlus),
          Expanded(
            child: Text(
              on ? "Screen will stay on" : "Faster with the app open",
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
          AppToggleSwitch(value: on, onChanged: _toggle, scale: 0.7),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context, bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Pressable(
        onTap: () => _toggle(!on),
        pressedScale: 0.97,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.mdPlus, AppSpacing.md, AppSpacing.md, AppSpacing.md),
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppRadii.mdPlus),
            ),
            color: on
                ? context.colors.green.withValues(alpha: 0.1)
                : context.colors.surfaceSecondary,
          ),
          child: Row(
            children: [
              Icon(
                on
                    ? Icons.brightness_high_rounded
                    : Icons.brightness_low_outlined,
                size: 20,
                color: on ? context.colors.green : context.colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Keep the screen on",
                      style: context.textTheme.headMd.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: AppType.semibold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "Uploads finish faster while the app is open.",
                      style: context.textTheme.bodySm.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              AppToggleSwitch(value: on, onChanged: _toggle),
            ],
          ),
        ),
      ),
    );
  }
}
