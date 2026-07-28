import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UserCard extends StatelessWidget {
  const UserCard({super.key});

  String _formatMemberSinceDate(DateTime date) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];

    final day = date.day;
    final suffix = _getDaySuffix(day);
    final month = months[date.month - 1];
    final year = date.year;

    return "Member since $day$suffix $month, $year";
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return "th";
    }
    switch (day % 10) {
      case 1:
        return "st";
      case 2:
        return "nd";
      case 3:
        return "rd";
      default:
        return "th";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, ap, _) {
        final user = ap.user;
        if (user == null) return const SizedBox.shrink();
        final joinedAt = user.createdAt;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: [
              BoxShadow(
                color: context.colors.textPrimary.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name ?? "",
                style: context.textTheme.headMd.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              if (joinedAt != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _formatMemberSinceDate(joinedAt),
                  style: context.textTheme.bodySm.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
