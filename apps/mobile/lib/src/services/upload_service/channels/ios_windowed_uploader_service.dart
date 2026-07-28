import "dart:developer" as dev;

import "package:flutter/services.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";

/// One part handed to the native windowed engine: a file slice + a fresh URL.
class WindowedPartPlan {
  const WindowedPartPlan({
    required this.partNumber,
    required this.offset,
    required this.length,
    required this.url,
    this.urlExpiresAt,
  });

  final int partNumber;
  final int offset;
  final int length;
  final String url;
  final DateTime? urlExpiresAt;

  Map<String, dynamic> toMap() => {
    "partNumber": partNumber,
    "offset": offset,
    "length": length,
    "url": url,
    if (urlExpiresAt != null)
      "urlExpiresAt": urlExpiresAt!.millisecondsSinceEpoch / 1000.0,
  };
}

/// The session manifest handed to native `beginSession`.
class WindowedSessionManifest {
  const WindowedSessionManifest({
    required this.sessionId,
    required this.fileUrl,
    required this.contentType,
    required this.fileSize,
    required this.chunkSize,
    required this.windowSize,
    required this.parts,
  });

  final String sessionId;
  final String fileUrl;
  final String contentType;
  final int fileSize;
  final int chunkSize;
  final int windowSize;
  final List<WindowedPartPlan> parts;

  Map<String, dynamic> toMap() => {
    "sessionId": sessionId,
    "fileUrl": fileUrl,
    "contentType": contentType,
    "fileSize": fileSize,
    "chunkSize": chunkSize,
    "windowSize": windowSize,
    "parts": parts.map((p) => p.toMap()).toList(),
  };
}

/// Events emitted by the native engine (event channel). Sealed so the
/// orchestrator handles each case exhaustively.
sealed class WindowedUploadEvent {
  const WindowedUploadEvent(this.sessionId);
  final String sessionId;

  /// Parse a raw native event map, or null if unrecognised.
  static WindowedUploadEvent? fromMap(Map<dynamic, dynamic> map) {
    final sessionId = map["sessionId"] as String? ?? "";
    switch (map["type"] as String?) {
      case "partCompleted":
        return WindowedPartCompleted(
          sessionId,
          partNumber: map["partNumber"] as int,
          etag: map["etag"] as String? ?? "",
        );
      case "partFailed":
        return WindowedPartFailed(
          sessionId,
          partNumber: map["partNumber"] as int,
          errorCode: map["errorCode"] as String? ?? "network",
          httpStatus: map["httpStatus"] as int?,
        );
      case "needUrls":
        return WindowedNeedUrls(
          sessionId,
          partNumbers: (map["partNumbers"] as List<dynamic>? ?? const [])
              .map((e) => e as int)
              .toList(),
        );
      case "progress":
        return WindowedProgress(
          sessionId,
          partNumber: (map["partNumber"] as num?)?.toInt() ?? 0,
          bytesSent: (map["bytesSent"] as num?)?.toInt() ?? 0,
          totalBytes: (map["totalBytes"] as num?)?.toInt() ?? 0,
        );
      case "sessionDrained":
        return WindowedSessionDrained(sessionId);
      default:
        return null;
    }
  }
}

class WindowedPartCompleted extends WindowedUploadEvent {
  const WindowedPartCompleted(
    super.sessionId, {
    required this.partNumber,
    required this.etag,
  });
  final int partNumber;
  final String etag;
}

class WindowedPartFailed extends WindowedUploadEvent {
  const WindowedPartFailed(
    super.sessionId, {
    required this.partNumber,
    required this.errorCode,
    this.httpStatus,
  });
  final int partNumber;
  final String errorCode;
  final int? httpStatus;
}

class WindowedNeedUrls extends WindowedUploadEvent {
  const WindowedNeedUrls(super.sessionId, {required this.partNumbers});
  final List<int> partNumbers;
}

class WindowedProgress extends WindowedUploadEvent {
  const WindowedProgress(
    super.sessionId, {
    required this.partNumber,
    required this.bytesSent,
    required this.totalBytes,
  });
  final int partNumber;
  final int bytesSent;
  final int totalBytes;
}

class WindowedSessionDrained extends WindowedUploadEvent {
  const WindowedSessionDrained(super.sessionId);
}

/// The windowed engine surface the coordinator drives — an interface so tests
/// can supply a fake without a platform channel (practice 09: hand-written fakes).
abstract interface class WindowedUploadEngine {
  Stream<WindowedUploadEvent> events();
  Future<Failure?> beginSession(WindowedSessionManifest manifest);
  Future<Failure?> provideUrls(String sessionId, List<WindowedPartPlan> parts);
  Future<Failure?> pauseSession(String sessionId);
  Future<Failure?> cancelSession(String sessionId);
  Future<(List<Map<String, dynamic>>, Failure?)> drainJournal({
    String? sessionId,
  });

  /// Free bytes available on the volume where the engine extracts chunk temp
  /// files — the figure the disk pre-flight gates on (doc 04 §4). Reads
  /// "available for important usage" so it reflects what iOS will actually let
  /// us write. Returns a very large value if the platform can't answer, so a
  /// channel hiccup never falsely blocks an upload (fail-open).
  Future<int> freeDiskBytes();

  /// Tell native to delete journal rows Dart has applied to Drift.
  Future<Failure?> acknowledgeDrain(List<Map<String, dynamic>> rows);

  /// Report the Flutter app's foreground/background state. While foregrounded
  /// the in-app UI owns progress, so native stays silent; while backgrounded
  /// (Dart frozen) native takes over the progress/stall/finish notifications.
  Future<Failure?> setAppForegrounded({required bool foregrounded});

  /// Cap how many part-PUT tasks native keeps in flight while the app is
  /// foregrounded — the adaptive concurrency gate (AIMD-tuned 5–10 by the
  /// coordinator from measured part durations). Backgrounded sessions ignore
  /// it and fill the full window. Process-lifetime on the native side (not
  /// journaled): a relaunched engine runs at its default until pushed again,
  /// which is why the coordinator re-pushes on every session start.
  Future<Failure?> setTransferConcurrency({required int maxInFlight});
}

/// Dart client for the native windowed upload engine — the sole upload path
/// (iOS only; the legacy in-process uploader and Android upload support were
/// removed). Mirrors the native `IosWindowedUploader` contract.
class IosWindowedUploaderService implements WindowedUploadEngine {
  IosWindowedUploaderService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _method = methodChannel ?? const MethodChannel("ios_windowed_uploader"),
       _events =
           eventChannel ?? const EventChannel("ios_windowed_uploader/events");

  static final IosWindowedUploaderService instance =
      IosWindowedUploaderService();

  final MethodChannel _method;
  final EventChannel _events;

  /// Cached so every [events] caller shares ONE underlying
  /// `receiveBroadcastStream()`. The native side keeps a single `eventSink`
  /// (onListen sets it, onCancel nils it), so independent broadcast streams
  /// would fight over it: a second subscriber's onListen overwrites the first's
  /// sink, and either subscriber cancelling nils it for everyone. Sharing one
  /// stream means a single native onListen (one sink, fanned out to all Dart
  /// listeners) and onCancel only when the last listener leaves.
  Stream<WindowedUploadEvent>? _eventStream;

  /// Typed stream of native engine events (unrecognised events are dropped).
  /// Errors (e.g. the native handler not yet registered) are logged and
  /// swallowed so a transient channel issue can't take down the app.
  @override
  Stream<WindowedUploadEvent> events() => _eventStream ??= _events
      .receiveBroadcastStream()
      .handleError((Object e) {
        dev.log("windowed uploader event stream error: $e", name: "windowed");
      })
      .map((e) => WindowedUploadEvent.fromMap(e as Map<dynamic, dynamic>))
      .where((e) => e != null)
      .cast<WindowedUploadEvent>()
      .asBroadcastStream();

  @override
  Future<Failure?> beginSession(WindowedSessionManifest manifest) =>
      _invoke("beginSession", manifest.toMap());

  @override
  Future<Failure?> provideUrls(
    String sessionId,
    List<WindowedPartPlan> parts,
  ) => _invoke("provideUrls", {
    "sessionId": sessionId,
    "parts": parts.map((p) => p.toMap()).toList(),
  });

  @override
  Future<Failure?> pauseSession(String sessionId) =>
      _invoke("pauseSession", {"sessionId": sessionId});

  @override
  Future<Failure?> cancelSession(String sessionId) =>
      _invoke("cancelSession", {"sessionId": sessionId});

  /// Drain native journal rows (completed/failed parts) accumulated while Dart
  /// was dead, so the caller can apply them to Drift.
  @override
  Future<(List<Map<String, dynamic>>, Failure?)> drainJournal({
    String? sessionId,
  }) async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>("drainJournal", {
        "sessionId": ?sessionId,
      });
      final rows = (raw ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return (rows, null);
    } catch (e) {
      return (<Map<String, dynamic>>[], _failure(e));
    }
  }

  /// Per-session native transfer snapshot for the dev page: each entry has
  /// `sessionId`, `state`, `uploaded`, `inFlight`. Lets us see, in a release
  /// build, whether the engine is actually scheduling parts (`inFlight` > 0) and
  /// whether they're completing (`uploaded` climbing). Returns `[]` on any error.
  Future<List<Map<String, dynamic>>> engineState() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>("engineState");
      return (raw ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      dev.log("windowed uploader engineState error: $e", name: "windowed");
      return const [];
    }
  }

  @override
  Future<Failure?> acknowledgeDrain(List<Map<String, dynamic>> rows) =>
      _invoke("acknowledgeDrain", {"rows": rows});

  @override
  Future<Failure?> setAppForegrounded({required bool foregrounded}) =>
      _invoke("setAppForegrounded", {"foregrounded": foregrounded});

  @override
  Future<Failure?> setTransferConcurrency({required int maxInFlight}) =>
      _invoke("setTransferConcurrency", {"maxInFlight": maxInFlight});

  /// A sentinel "plenty of disk" reading used when the native side can't be
  /// reached, so the pre-flight fails open rather than blocking uploads.
  static const int _freeDiskFailOpen = 1 << 60; // ~1.15 EB

  @override
  Future<int> freeDiskBytes() async {
    try {
      final raw = await _method.invokeMethod<dynamic>("freeDiskBytes");
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return _freeDiskFailOpen;
    } catch (e) {
      // Channel not registered / platform error — never block on a read failure.
      dev.log("windowed uploader freeDiskBytes error: $e", name: "windowed");
      return _freeDiskFailOpen;
    }
  }

  Future<Failure?> _invoke(String method, Map<String, dynamic> args) async {
    try {
      await _method.invokeMethod<void>(method, args);
      return null;
    } catch (e) {
      // Catches PlatformException and MissingPluginException (handler not yet
      // registered) alike — never throw across this boundary.
      return _failure(e);
    }
  }

  Failure _failure(Object e) => Failure(
    message: e is PlatformException
        ? (e.message ?? "Windowed uploader error")
        : e.toString(),
    code: ErrorType.unknown,
  );
}
