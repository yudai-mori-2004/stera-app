import "dart:async";
import "dart:developer" as dev;
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_error_overlay.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_low_quality_banner.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_preview_area.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_controls.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_recording_indicator.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_status_bar.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/exit_ar_recorder_warning_dialog.dart";
import "package:stera/src/modules/upload/providers/managers/orphan_recovery_sweeper.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArRecorderPage extends StatefulWidget {
  static const String routeName = "/ar-recorder";

  const ArRecorderPage({super.key});

  @override
  State<ArRecorderPage> createState() => _ArRecorderPageState();
}

class _ArRecorderPageState extends State<ArRecorderPage> {
  late final ArRecorderProvider _arp;
  final MethodChannel _arChannel = ArRecorderChannel.channel;

  VoiceCommandService? _voiceService;
  bool _audioCueInitialized = false;
  bool _voiceDisableToastShown = false;

  // Battery safeguard: warns at 30%/25%/20% and auto-stops at ≤19% while
  // recording (copy advertises 20% as the cutoff).
  late final BatteryMonitorService _batteryMonitor;
  bool _batteryAutoStopFired = false;

  @override
  void initState() {
    super.initState();
    _arp = context.read<ArRecorderProvider>();
    _arChannel.setMethodCallHandler(_handleNativeCall);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight]);

    _batteryMonitor = BatteryMonitorService(
      onLowBatteryWarning: _handleLowBatteryWarning,
      onCriticalBattery: _handleCriticalBattery,
    );
    _arp.addListener(_syncBatteryMonitor);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AppToast.info(
        title: "Hold your device in landscape mode",
        description: "Keep the home button on the left for best results.",
        holdDuration: 4,
      );
      await _arp.initializeSession();
      if (!mounted) return;
      await _initAudioCueServiceIfNeeded();
      await _initVoiceServiceIfNeeded();
    });
  }

  Future<void> _initAudioCueServiceIfNeeded() async {
    if (_arp.enableAudioCues && !_audioCueInitialized) {
      await AudioCueService.init();
      _audioCueInitialized = true;
    }
  }

  Future<void> _initVoiceServiceIfNeeded() async {
    if (!_arp.enableVoiceCommands) return;
    if (_voiceService != null) return;
    _voiceService = VoiceCommandService(onCommand: _handleVoiceCommand);
    _voiceService!.isDisabled.addListener(_onVoiceDisabledChanged);
    final ready = await _voiceService!.init();
    if (ready && mounted && !_voiceService!.voiceDisabledForSession) {
      _voiceService!.startListening();
    }
  }

  void _onVoiceDisabledChanged() {
    if (_voiceService == null ||
        !_voiceService!.isDisabled.value ||
        _voiceDisableToastShown ||
        !mounted) {
      return;
    }
    _voiceDisableToastShown = true;
    AppToast.warning(
      title: "Voice commands disabled for stability",
      description: "Use on-screen Start/Stop controls.",
      holdDuration: 5,
    );
  }

  void _handleVoiceCommand(VoiceCommand cmd) {
    switch (cmd) {
      case VoiceCommand.startRecording:
        if (_arp.state == ArRecorderState.ready) {
          HapticFeedback.mediumImpact();
          unawaited(_startRecordingFromVoice());
        }
      case VoiceCommand.stopRecording:
        if (_arp.isRecording || _arp.isPaused) {
          HapticFeedback.heavyImpact();
          unawaited(_handleStopRecording(source: "voice"));
        }
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == ArRecorderMethod.lowStorageWarning.methodName) {
      if (mounted) {
        AppToast.warning(
          title: "Low storage",
          description: "Recording will stop soon — free up space.",
          holdDuration: 5,
        );
      }
      if (_arp.enableAudioCues) {
        await _playCueWithVoicePause(AudioCueService.playLowStorageCue);
      }
      return;
    }

    if (call.method == ArRecorderMethod.storageCritical.methodName) {
      dev.log("ArRecorderPage: Storage critical — auto-stopping recording");
      if (_arp.isRecording || _arp.isPaused) {
        unawaited(_handleStopRecording(source: "storage_critical"));
      }
    }
  }

  /// Starts/stops the battery monitor to mirror the active recording state.
  /// The monitor only runs while recording (or paused) so we never auto-stop
  /// or nag about battery on the idle preview screen.
  void _syncBatteryMonitor() {
    final active = _arp.isRecording || _arp.isPaused;
    if (active && !_batteryMonitor.isRunning) {
      _batteryAutoStopFired = false;
      _batteryMonitor.start();
    } else if (!active && _batteryMonitor.isRunning) {
      _batteryMonitor.stop();
    }
  }

  /// Low-battery threshold (30% / 25%) crossed while recording: warn the user
  /// audibly and visually. Recording continues.
  Future<void> _handleLowBatteryWarning() async {
    if (!mounted) return;
    AppToast.warning(
      title: "Battery low",
      description: "Recording will stop automatically at 20%.",
      holdDuration: 5,
    );
    if (_arp.enableAudioCues) {
      await _playCueWithVoicePause(AudioCueService.playLowBatteryCue);
    }
  }

  /// Critical battery ([BatteryMonitorService.criticalThreshold] or below)
  /// reached while recording: auto-stop in every case.
  Future<void> _handleCriticalBattery() async {
    if (_batteryAutoStopFired) return;
    if (!(_arp.isRecording || _arp.isPaused)) return;
    _batteryAutoStopFired = true;
    dev.log("ArRecorderPage: Battery critical — auto-stopping recording");
    if (mounted) {
      AppToast.warning(
        title: "Battery critically low",
        description: "Recording stopped to protect your device.",
        holdDuration: 5,
      );
    }
    await _handleStopRecording(source: "low_battery");
  }

  /// Plays an audio cue with STT paused so they never compete for AVFoundation.
  /// Stops STT -> plays cue -> waits for completion -> restarts STT.
  Future<void> _playCueWithVoicePause(Future<void> Function() playCue) async {
    final hadVoice =
        _voiceService != null && !_voiceService!.voiceDisabledForSession;
    if (hadVoice) {
      _voiceService!.stopListening();
      // stopListening() tears the STT audio session down asynchronously
      // (category restore + deactivate land a beat later). Let that settle
      // BEFORE the cue starts, or the teardown silences the cue mid-play.
      await Future.delayed(const Duration(milliseconds: 350));
    }
    await _initAudioCueServiceIfNeeded();
    await playCue();
    if (hadVoice && mounted && !_voiceService!.voiceDisabledForSession) {
      // Small delay to let AVAudioSession settle before STT reclaims it.
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _voiceService!.startListening();
    }
  }

  Future<void> _startRecordingFromUi() => _startRecording(source: "ui");

  Future<void> _startRecordingFromVoice() => _startRecording(source: "voice");

  /// Shared start path for the record button and the "start" voice command.
  /// Runs a battery pre-flight first: hard-block below
  /// [BatteryMonitorService.minStartThreshold] (22%), and below
  /// [BatteryMonitorService.warnStartThreshold] (30%) allow the start but chase
  /// the start cue with an audible low-battery warning. The battery cues are
  /// spaced 10s apart inside [AudioCueService] so they never overlap.
  Future<void> _startRecording({required String source}) async {
    if (_arp.state != ArRecorderState.ready) return;

    final batteryLevel = await _batteryMonitor.currentLevel();
    if (!mounted) return;
    if (batteryLevel != null &&
        batteryLevel < BatteryMonitorService.minStartThreshold) {
      await _rejectStartForLowBattery(batteryLevel);
      return;
    }

    _voiceService?.stopListening();
    await _arp.startRecording(source: source);
    if (_arp.enableAudioCues && _arp.isRecording) {
      final warnLowBattery =
          batteryLevel != null &&
          batteryLevel < BatteryMonitorService.warnStartThreshold;
      await _playCueWithVoicePause(() async {
        await AudioCueService.playStartCue();
        if (warnLowBattery) await AudioCueService.playWarnLowBatteryCue();
      });
    } else {
      if (!_arp.isRecording) _showStartFailureToast();
      _restartVoiceIfNeeded();
    }
  }

  /// Below [BatteryMonitorService.minStartThreshold]: refuse to start, tell the
  /// user why (toast), and play the low-battery warning cue. Leaves the
  /// recorder in READY so no error overlay shows.
  Future<void> _rejectStartForLowBattery(int level) async {
    dev.log("ArRecorderPage: start blocked — battery $level% too low");
    if (mounted) {
      AppToast.warning(
        title: "Battery too low to record",
        description:
            "Charge to at least ${BatteryMonitorService.minStartThreshold}% "
            "before starting a recording.",
        holdDuration: 5,
      );
    }
    if (_arp.enableAudioCues) {
      await _playCueWithVoicePause(AudioCueService.playWarnLowBatteryCue);
    }
  }

  /// Surfaces a start-recording rejection that leaves the recorder in READY
  /// (so [ArErrorOverlay] never shows). Maps the known native pre-flight
  /// errors to actionable copy and falls back to the raw message.
  void _showStartFailureToast() {
    if (!mounted) return;
    final raw = _arp.errorMessage;
    if (raw != null && raw.contains("Insufficient storage")) {
      AppToast.warning(
        title: "Not enough storage to record",
        description:
            _storageShortfallDescription(raw) ??
            "Free up space on this device and try again.",
        holdDuration: 5,
      );
    } else if (raw != null && raw.contains("Tracking not stable")) {
      AppToast.warning(
        title: "Camera tracking not ready",
        description: "Hold the phone steady for a moment, then try again.",
        holdDuration: 5,
      );
    } else {
      AppToast.error(
        title: "Couldn't start recording",
        description: raw,
        holdDuration: 5,
      );
    }
  }

  /// Parses the native headroom message ("Estimated `e` bytes exceeds `p`% of
  /// available storage `a` bytes") into "Free up about X GB". Returns null if
  /// the format ever changes so the caller can use generic copy.
  String? _storageShortfallDescription(String raw) {
    final match = RegExp(
      r"Estimated (\d+) bytes exceeds (\d+)% of available storage (\d+) bytes",
    ).firstMatch(raw);
    if (match == null) return null;
    final estimated = int.parse(match.group(1)!);
    final percent = int.parse(match.group(2)!);
    final available = int.parse(match.group(3)!);
    if (percent <= 0) return null;
    final shortfallBytes = (estimated * 100 ~/ percent) - available;
    if (shortfallBytes <= 0) return null;
    final shortfallGb = (shortfallBytes / 1e9).toStringAsFixed(1);
    return "Free up about $shortfallGb GB on this device and try again.";
  }

  void _restartVoiceIfNeeded() {
    if (_voiceService == null || _voiceService!.voiceDisabledForSession) return;
    if (!mounted) return;
    _voiceService!.startListening();
  }

  Future<void> _confirmDiscardAndExit() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return const ExitArRecorderWarningDialog();
      },
    );
    if (shouldDiscard == true && mounted) {
      await _arp.cancelRecording(source: "discard_dialog");
      if (mounted) AppRouter.pop();
    }
  }

  Future<void> _handleStopRecording({String source = "ui"}) async {
    _voiceService?.stopListening();
    await _arp.stopRecording(source: source);
    if (_arp.enableAudioCues) {
      // No voice restart needed after stop — we navigate away.
      await _initAudioCueServiceIfNeeded();
      await AudioCueService.playStopCue();
    }
    if (mounted && _arp.outputDirectory != null) {
      Navigator.of(context).pop(_arp.outputDirectory);
    }
  }

  @override
  void dispose() {
    _arChannel.setMethodCallHandler(null);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _arp.removeListener(_syncBatteryMonitor);
    _batteryMonitor.dispose();
    _voiceService?.isDisabled.removeListener(_onVoiceDisabledChanged);
    _voiceService?.dispose();
    if (_audioCueInitialized) {
      unawaited(AudioCueService.dispose());
    }
    unawaited(_arp.shutdownSessionForPageExit());
    // Safety net: a take can land on disk without its Upload row when the
    // finalize event is missed. Sweep for orphans 3× at 10 s intervals after
    // leaving this page; the sweeper is static so it outlives this state.
    OrphanRecoverySweeper.scheduleAfterRecorderExit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecordingActive = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isRecording || arp.isPaused,
    );
    final isRecording = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isRecording,
    );
    final isPaused = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isPaused,
    );
    final showLowQualityBanner = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isLowQualityMode,
    );
    final showError = context.select<ArRecorderProvider, bool>(
      (arp) => arp.state == ArRecorderState.error,
    );

    return PopScope(
      canPop: !isRecordingActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscardAndExit();
      },
      child: Scaffold(
        backgroundColor: context.colors.neutralBlack,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ArPreviewArea(),
              const Positioned(top: 8, left: 8, child: ArStatusBar()),
              Positioned(
                top: 8,
                right: 8,
                child: ArRecordingIndicator(
                  isRecording: isRecording,
                  isPaused: isPaused,
                ),
              ),
              if (showLowQualityBanner)
                const Positioned(
                  top: 64,
                  left: 16,
                  right: 16,
                  child: ArLowQualityBanner(),
                ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: ArRecordingControls(
                  onStartPressed: _startRecordingFromUi,
                  onStopPressed: _handleStopRecording,
                ),
              ),
              if (showError) const ArErrorOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}
