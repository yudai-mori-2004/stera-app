import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:solar_icons/solar_icons.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_sizes.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/app_header.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/modules/ar_recorder/helpers/ar_recorder_launcher.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_settings_pannel/ar_recording_settings_header_button.dart";
import "package:stera/src/modules/capture/ui/widgets/capture_recordings_section.dart";
import "package:stera/src/modules/demo/ui/widgets/app_demo_video_inline_intro_card.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";
import "package:stera/src/services/api/enums/error_type.dart";

/// The whole app shell in a `NO_AUTH_MODE` build: record, then browse and
/// preview what was recorded.
///
/// Replaces `NavigationPage` at `/root`. There is no bottom nav because there
/// are only two surfaces — this page and the MCAP preview it pushes — and no
/// upload library or home feed to switch between. Notably it does *not* port
/// `NavigationPage`'s notification-permission prompt: that exists solely to
/// unblock upload notifications.
class CapturePage extends StatefulWidget {
  static const String routeName = "/capture";

  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<RecordingsProvider>().loadSessions());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A session can finish finalizing while the app is backgrounded, and sizes
    // only settle once the mcap footer lands — so re-read on the way back in.
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(context.read<RecordingsProvider>().loadSessions());
  }

  Future<void> _startRecording() async {
    if (_launching) return;
    setState(() => _launching = true);

    final (sessionDir, failure) = await ArRecorderLauncher.launch(context);

    if (!mounted) return;
    setState(() => _launching = false);

    if (sessionDir == null) {
      // A cancel is a deliberate back-out, and an unsupported device already
      // got its own sheet — neither deserves an error toast.
      if (failure != null && failure.code != ErrorType.cancelled) {
        AppToast.show(title: failure.message, appToastType: AppToastType.error);
      }
      return;
    }

    final provider = context.read<RecordingsProvider>();
    // Show the session straight away, then poll for the mcap footer in the
    // background: only the preview tap is gated on finalization, not the row.
    await provider.loadSessions();
    unawaited(provider.trackFinalization(sessionDir));
  }

  @override
  Widget build(BuildContext context) {
    // Outer Scaffold + textured Container + inner transparent Scaffold, the
    // same shell `ProfilePage` uses. In the authed build `NavigationPage`
    // supplies the outer Scaffold (it owns the bottom nav) and `HomePage` the
    // inner one; with no bottom nav this page has to carry both itself, or the
    // texture stops short of the screen edges.
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
              text1: "Stera",
              text2: " by FPV Labs",
              customStyle2: context.textTheme.head3XlHandjet.copyWith(
                fontWeight: AppType.bold,
                fontSize: AppType.xl3Plus,
              ),
              actions: const [ArRecordingSettingsHeaderButton()],
            ),
            // The content scrolls as one column and only the action is pinned —
            // the same footer layout `AddUploadPage` uses for `UploadActions`.
            // The demo card has an intrinsic height, so leaving it and the
            // recordings grid as siblings of a pinned button overflows a short
            // screen.
            body: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    backgroundColor: context.colors.surfacePrimary,
                    color: context.colors.textPrimary,
                    onRefresh: () =>
                        context.read<RecordingsProvider>().loadSessions(),
                    child: const SingleChildScrollView(
                      physics: AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          // Still thumbnail when DEMO_VIDEO_URL is unset (common
                          // in NO_AUTH_MODE); inline playback when it is set.
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.none,
                            ),
                            child: AppDemoVideoInlineIntroCard(),
                          ),
                          AppSpacing.gapLg,
                          CaptureRecordingsSection(),
                        ],
                      ),
                    ),
                  ),
                ),
                AppSpacing.gapXl,
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ).copyWith(bottom: AppSpacing.lg),
                  child: AppButton(
                    key: const ValueKey("start-recording-button"),
                    type: ButtonType.primary,
                    size: ButtonSizes.lg,
                    text: "Start Recording",
                    isLoading: _launching,
                    leadingIcon: Icon(
                      SolarIconsOutline.videocameraRecord,
                      size: 20,
                      color: context.colors.textInversePrimary,
                    ),
                    onPressed: _startRecording,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
