import "package:flutter/material.dart";
import "package:stera/src/core/common/widgets/app_header_action_button.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/ar_recording_settings_panel.dart";

class ArRecordingSettingsHeaderButton extends StatelessWidget {
  const ArRecordingSettingsHeaderButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppHeaderActionButton(
      icon: Icons.tune,
      semanticLabel: "Recording settings",
      onTap: () => ArRecordingSettingsPanel.show(context),
    );
  }
}
