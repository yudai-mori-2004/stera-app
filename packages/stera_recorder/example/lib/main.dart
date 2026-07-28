import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";
import "package:stera_recorder/stera_recorder.dart";

void main() => runApp(const ExampleApp());

/// Camera permission, backed by `permission_handler`.
///
/// The recorder only ever *checks* — requesting is the host app's call, which
/// this example does once in [_RecorderPageState.initState].
class ExamplePermissions implements RecorderPermissions {
  /// Creates the permission adapter.
  const ExamplePermissions();

  @override
  Future<bool> isCameraPermissionGranted() async =>
      (await Permission.camera.status).isGranted;

  @override
  Future<bool> openSettings() => openAppSettings();
}

/// The example app shell.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "stera_recorder example",
      theme: ThemeData.dark(),
      home: const RecorderPage(),
    );
  }
}

/// A single screen: camera preview, session status, and a record button.
class RecorderPage extends StatefulWidget {
  /// Creates the recorder screen.
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  // A real app persists these — see `RecorderPreferences`. The in-memory store
  // keeps the example to one screen, at the cost of forgetting settings on exit.
  late final ArRecorderProvider _recorder = ArRecorderProvider(
    preferences: InMemoryRecorderPreferences(),
    permissions: const ExamplePermissions(),
  );

  String? _lastOutputDirectory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Permission.camera.request();
      if (!mounted) return;
      await _recorder.initializeSession();
    });
  }

  @override
  void dispose() {
    _recorder.shutdownSessionForPageExit();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() => _recorder.startRecording();

  Future<void> _stop() async {
    await _recorder.stopRecording();
    if (!mounted) return;
    setState(() => _lastOutputDirectory = _recorder.outputDirectory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _recorder,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _Preview(recorder: _recorder),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _StatusChip(recorder: _recorder),
                ),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: _Controls(
                    recorder: _recorder,
                    onStart: _start,
                    onStop: _stop,
                    lastOutputDirectory: _lastOutputDirectory,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.recorder});

  final ArRecorderProvider recorder;

  @override
  Widget build(BuildContext context) {
    final textureId = recorder.textureId;
    if (textureId == null) {
      return Center(
        child: Text(
          switch (recorder.state) {
            ArRecorderState.error =>
              recorder.errorMessage ?? "Failed to start the AR session",
            ArRecorderState.disposed => "Session ended",
            _ => "Starting the AR session…",
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    // The texture keeps the recorded frame's aspect ratio; fitting to width and
    // clipping shows a slightly tighter view without changing what's recorded.
    final width = recorder.previewWidth;
    final height = recorder.previewHeight;
    final aspectRatio = (width != null && height != null && height > 0)
        ? width / height
        : 16 / 9;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fitWidth,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: aspectRatio,
            height: 1,
            child: Texture(textureId: textureId),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.recorder});

  final ArRecorderProvider recorder;

  @override
  Widget build(BuildContext context) {
    final seconds = recorder.recordingDuration.inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        "${recorder.state.name} · ${recorder.trackingState.label}"
        "${recorder.isRecording ? " · ${seconds}s" : ""}",
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.recorder,
    required this.onStart,
    required this.onStop,
    required this.lastOutputDirectory,
  });

  final ArRecorderProvider recorder;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final String? lastOutputDirectory;

  @override
  Widget build(BuildContext context) {
    final isActive = recorder.isRecording || recorder.isPaused;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lastOutputDirectory != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "Saved to $lastOutputDirectory",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: switch (recorder.state) {
            ArRecorderState.ready when !isActive => onStart,
            ArRecorderState.recording || ArRecorderState.paused => onStop,
            _ => null,
          },
          style: FilledButton.styleFrom(
            backgroundColor: isActive ? Colors.red : Colors.white,
            foregroundColor: isActive ? Colors.white : Colors.black,
            minimumSize: const Size(160, 48),
          ),
          child: Text(isActive ? "Stop" : "Record"),
        ),
      ],
    );
  }
}
