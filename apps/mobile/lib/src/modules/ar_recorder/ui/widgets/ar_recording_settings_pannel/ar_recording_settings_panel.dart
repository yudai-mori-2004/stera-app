import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list_tile.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/common/widgets/toggle_row.dart";
import "package:stera/src/core/config/feature_gates.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/inset_divider.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/rgb_video_resolution_row.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/section_label.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArRecordingSettingsPanel extends StatelessWidget {
  const ArRecordingSettingsPanel({super.key});

  static Future<void> show(BuildContext context) {
    final arp = context.read<ArRecorderProvider>();

    return showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: arp,
        child: const ArRecordingSettingsPanel(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 20 + MediaQuery.viewInsetsOf(context).bottom;

    return Consumer<ArRecorderProvider>(
      builder: (_, arp, _) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: context.colors.surfaceSecondary,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lgPlus)),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: context.h * 0.75),
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.sm, AppSpacing.lgPlus, bottomPad),
              child: ListView(
                shrinkWrap: true,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: AppSpacing.lgPlus),
                  SheetHeader(
                    title: "Recording Settings",
                    subtitle:
                        "Set options before you start the camera so capture matches "
                        "what you need.",
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: AppSpacing.lgPlus),
                  if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SectionLabel(text: "Camera settings"),
                    const SizedBox(height: AppSpacing.smPlus),
                    InteractiveListTile(
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RgbVideoResolutionRow(
                            value: arp.rgbVideoResolution,
                            onChanged: (v) => arp.rgbVideoResolution = v,
                          ),
                          const InsetDivider(),
                          ToggleRow(
                            title: "Auto Focus",
                            subtitle:
                                "Let the camera adjust focus automatically as the scene changes",
                            value: arp.autoFocus,
                            onChanged: (v) => arp.autoFocus = v,
                          ),
                          const InsetDivider(),
                          ToggleRow(
                            title: "Auto Exposure",
                            subtitle:
                                "Let the camera adjust exposure automatically. Turn off to lock exposure once it settles, keeping brightness constant across the take.",
                            value: arp.autoExposure,
                            onChanged: (v) => arp.autoExposure = v,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const SectionLabel(text: "Tracking & timing"),
                    const SizedBox(height: AppSpacing.smPlus),
                    InteractiveList(
                      children: [
                        InteractiveListTile(
                          title: "Sync Recording Rate",
                          subTitle:
                              "Use the same Hz for RGB, depth, and point cloud",
                          subTitleMaxLines: 2,
                          action: InteractiveListTileAction.toggle,
                          switchValue: arp.syncHz,
                          onToggle: (v) => arp.syncHz = v,
                          hzOptions: arp.syncHz
                              ? arp.rgbVideoResolution.spatialHzOptions
                              : null,
                          hzValue: arp.rgbHz,
                          onHzChanged: (v) => arp.rgbHz = v,
                        ),
                        if (FeatureGates.isVisible(GatedFeature.arkitImu))
                          InteractiveListTile(
                            title: "ARKit IMU",
                            subTitle:
                                "Record ARKit's VIO-fused orientation + angular velocity on /arkit/imu.",
                            subTitleMaxLines: 2,
                            action: InteractiveListTileAction.toggle,
                            switchValue: arp.enableInertialDerived,
                            onToggle: (v) => arp.enableInertialDerived = v,
                            hzOptions: arp.enableInertialDerived
                                ? RecordingConfig.supportedArkitFps
                                      .where(
                                        (fps) =>
                                            fps <=
                                            arp.rgbVideoResolution.maxArkitFps,
                                      )
                                      .toList()
                                : null,
                            hzValue: arp.arkitFps,
                            onHzChanged: (v) => arp.arkitFps = v,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  const SectionLabel(text: "Data streams"),
                  const SizedBox(height: AppSpacing.smPlus),
                  InteractiveList(
                    children: [
                      InteractiveListTile(
                        title: "RGB Camera",
                        subTitle: "Compressed JPEG video frames",
                        action: InteractiveListTileAction.toggle,
                        switchValue: arp.recordRgb,
                        onToggle: (v) => arp.recordRgb = v,
                        hzOptions:
                            defaultTargetPlatform == TargetPlatform.iOS &&
                                !arp.syncHz
                            ? arp.rgbVideoResolution.spatialHzOptions
                            : null,
                        hzValue: arp.rgbHz,
                        onHzChanged: (v) => arp.rgbHz = v,
                      ),
                      InteractiveListTile(
                        title: "IMU",
                        subTitle: "Gyroscope & accelerometer data",
                        action: InteractiveListTileAction.toggle,
                        switchValue: arp.recordImu,
                        onToggle: (v) => arp.recordImu = v,
                        hzOptions:
                            defaultTargetPlatform == TargetPlatform.iOS &&
                                arp.recordImu
                            ? RecordingConfig.supportedImuHz
                            : null,
                        hzValue: arp.imuHz,
                        onHzChanged: (v) => arp.imuHz = v,
                      ),
                      if (FeatureGates.isVisible(GatedFeature.depth))
                        InteractiveListTile(
                          title: "Depth",
                          subTitle: "Depth map (LiDAR)",
                          action: InteractiveListTileAction.toggle,
                          switchValue: arp.recordDepth,
                          onToggle: (v) => arp.recordDepth = v,
                          hzOptions:
                              defaultTargetPlatform == TargetPlatform.iOS &&
                                  !arp.syncHz
                              ? arp.rgbVideoResolution.spatialHzOptions
                              : null,
                          hzValue: arp.depthHz,
                          onHzChanged: (v) => arp.depthHz = v,
                        ),
                      InteractiveListTile(
                        title: "Point Cloud",
                        subTitle: "3D feature point cloud",
                        action: InteractiveListTileAction.toggle,
                        switchValue: arp.recordPointCloud,
                        onToggle: (v) => arp.recordPointCloud = v,
                        hzOptions:
                            defaultTargetPlatform == TargetPlatform.iOS &&
                                !arp.syncHz
                            ? arp.rgbVideoResolution.spatialHzOptions
                            : null,
                        hzValue: arp.pointCloudHz,
                        onHzChanged: (v) => arp.pointCloudHz = v,
                      ),
                      InteractiveListTile(
                        title: "Mesh",
                        subTitle: "3D mesh reconstruction",
                        action: InteractiveListTileAction.toggle,
                        switchValue: arp.recordMesh,
                        onToggle: (v) => arp.recordMesh = v,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionLabel(text: "Voice & audio"),
                  const SizedBox(height: AppSpacing.smPlus),
                  InteractiveList(
                    children: [
                      InteractiveListTile(
                        title: "Voice Commands",
                        subTitle:
                            "Say 'start recording' or 'stop recording' hands-free",
                        action: InteractiveListTileAction.toggle,
                        subTitleMaxLines: 2,
                        switchValue: arp.enableVoiceCommands,
                        onToggle: (v) => arp.enableVoiceCommands = v,
                      ),
                      InteractiveListTile(
                        title: "Audio Cues",
                        subTitle: "Play a sound when recording starts or stops",
                        action: InteractiveListTileAction.toggle,
                        subTitleMaxLines: 2,
                        switchValue: arp.enableAudioCues,
                        onToggle: (v) => arp.enableAudioCues = v,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
