import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — Flutter bridge for the windowed engine (the ONLY file importing
// Flutter, per the triad rule). Compiles in Xcode. Marshals the 5-call method
// channel and the event channel onto `ChunkWindowManager`.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Flutter)
import Flutter

public class IosWindowedUploaderMethodChannelHandler: NSObject {
    private static let channelName = "ios_windowed_uploader"
    private static let eventChannelName = "ios_windowed_uploader/events"

    private let engine: ChunkWindowManager
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel

    public init(binaryMessenger: FlutterBinaryMessenger) {
        self.engine = ChunkWindowManager.shared
        self.methodChannel = FlutterMethodChannel(
            name: IosWindowedUploaderMethodChannelHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        self.eventChannel = FlutterEventChannel(
            name: IosWindowedUploaderMethodChannelHandler.eventChannelName,
            binaryMessenger: binaryMessenger
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        eventChannel.setStreamHandler(self)
        print("✅ IosWindowedUploaderMethodChannelHandler: initialized")
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "beginSession":
            guard let manifest = parseManifest(call.arguments) else {
                return result(argError())
            }
            engine.beginSession(manifest)
            result(nil)
        case "provideUrls":
            guard let args = call.arguments as? [String: Any],
                  let sessionId = args["sessionId"] as? String else {
                return result(argError())
            }
            engine.provideUrls(sessionId: sessionId, parts: parseParts(args["parts"]))
            result(nil)
        case "pauseSession":
            guard let id = sessionId(call) else { return result(argError()) }
            engine.pauseSession(sessionId: id)
            result(nil)
        case "cancelSession":
            guard let id = sessionId(call) else { return result(argError()) }
            engine.cancelSession(sessionId: id)
            result(nil)
        case "drainJournal":
            result(engine.drainJournal(sessionId: sessionId(call)))
        case "engineState":
            result(engine.engineState())
        case "acknowledgeDrain":
            guard let args = call.arguments as? [String: Any],
                  let rows = args["rows"] as? [[String: Any]] else {
                return result(argError())
            }
            engine.acknowledgeDrain(rows)
            result(nil)
        case "setTransferConcurrency":
            // Adaptive foreground gate from Dart's AIMD tuner (5–10).
            guard
                let maxInFlight = ((call.arguments as? [String: Any])?["maxInFlight"]
                    as? NSNumber)?.intValue
            else {
                return result(argError())
            }
            engine.setTransferConcurrency(maxInFlight: maxInFlight)
            result(nil)
        case "setAppForegrounded":
            // Lifecycle hint from Dart: drives whether native owns notifications.
            let value = (call.arguments as? [String: Any])?["foregrounded"] as? Bool
            engine.appForegrounded = value ?? false
            result(nil)
        case "freeDiskBytes":
            // Int64 can exceed 32-bit; hand Flutter an NSNumber so it survives
            // as an int on the Dart side.
            result(NSNumber(value: engine.freeDiskBytes()))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func sessionId(_ call: FlutterMethodCall) -> String? {
        (call.arguments as? [String: Any])?["sessionId"] as? String
    }

    private func parseManifest(_ arguments: Any?) -> UploadSessionManifest? {
        guard let a = arguments as? [String: Any],
              let sessionId = a["sessionId"] as? String,
              let fileUrl = a["fileUrl"] as? String,
              let contentType = a["contentType"] as? String,
              let fileSize = (a["fileSize"] as? NSNumber)?.int64Value,
              let chunkSize = (a["chunkSize"] as? NSNumber)?.intValue,
              let windowSize = (a["windowSize"] as? NSNumber)?.intValue
        else { return nil }
        return UploadSessionManifest(
            sessionId: sessionId, fileUrl: fileUrl, contentType: contentType,
            fileSize: fileSize, chunkSize: chunkSize, windowSize: windowSize,
            parts: parseParts(a["parts"])
        )
    }

    private func parseParts(_ raw: Any?) -> [UploadPartPlan] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { p in
            guard let partNumber = (p["partNumber"] as? NSNumber)?.intValue,
                  let offset = (p["offset"] as? NSNumber)?.int64Value,
                  let length = (p["length"] as? NSNumber)?.intValue,
                  let url = p["url"] as? String
            else { return nil }
            let expires = (p["urlExpiresAt"] as? NSNumber)
                .map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UploadPartPlan(
                partNumber: partNumber, offset: offset, length: length,
                url: url, urlExpiresAt: expires
            )
        }
    }

    private func argError() -> FlutterError {
        FlutterError(code: "INVALID_ARGUMENT", message: "Missing/invalid arguments", details: nil)
    }
}

extension IosWindowedUploaderMethodChannelHandler: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        engine.eventSink = { event in events(event) }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        engine.eventSink = nil
        return nil
    }
}

#else
public class IosWindowedUploaderMethodChannelHandler: NSObject {}
#endif
