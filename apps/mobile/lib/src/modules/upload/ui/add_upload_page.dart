import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_card.dart";
import "package:stera/src/core/common/widgets/app_header_action_button.dart";
import "package:stera/src/core/common/widgets/app_popup_menu/app_popup_menu.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/ar_recording_settings_header_button.dart";
import "package:stera/src/modules/upload/ui/views/not_started_videos_grid_view.dart";
import "package:stera/src/modules/upload/ui/widgets/recover_recordings_action.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_actions.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_guidelines_bottomsheet.dart";
import "package:stera/src/core/common/widgets/app_header.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class AddUploadPage extends StatefulWidget {
  static const String routeName = "/add-upload";

  const AddUploadPage({super.key});

  @override
  State<AddUploadPage> createState() => _AddUploadPageState();
}

/// A header action that can render either inline as an icon button or as a row
/// in the overflow menu.
typedef _HeaderAction = ({String label, IconData icon, VoidCallback onTap});

class _AddUploadPageState extends State<AddUploadPage> {
  /// Total icon buttons the header can show before the title starts losing
  /// room; past this the collapsible actions fold into the overflow menu.
  static const int _maxHeaderActions = 3;

  /// Buttons that always occupy a header slot and can never collapse: the
  /// recording-settings button here, plus the profile button [AppHeader] adds.
  static const int _fixedHeaderActions = 2;

  List<_HeaderAction> _collapsibleActions(BuildContext context) => [
    (
      label: "Recover recordings",
      icon: Icons.restore,
      onTap: () => RecoverRecordingsAction.run(context),
    ),
  ];

  List<Widget> _headerActions(BuildContext context) {
    final actions = _collapsibleActions(context);

    return [
      if (actions.length + _fixedHeaderActions > _maxHeaderActions)
        Semantics(
          label: "More actions",
          button: true,
          child: AppPopupMenu(
            items: [
              for (final action in actions)
                AppPopupMenuItem(label: action.label, onSelected: action.onTap),
            ],
            child: const AppHeaderActionButton(icon: Icons.more_horiz),
          ),
        )
      else
        for (final action in actions)
          AppHeaderActionButton(
            icon: action.icon,
            semanticLabel: action.label,
            onTap: action.onTap,
          ),
      const ArRecordingSettingsHeaderButton(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            text1: "Start ",
            text2: "Recording",
            actions: _headerActions(context),
          ),
          body: Column(
            children: [
              Expanded(
                child: AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ).copyWith(top: 16),
                  child: const SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UploadGuidelinesCard(),
                        SizedBox(height: AppSpacing.xl),
                        NotStartedVideosGridView(),
                        SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const UploadActions(),
            ],
          ),
        ),
      ),
    );
  }
}
