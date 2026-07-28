import Foundation
import AVFoundation
import Flutter
import UIKit

/// Handles Flutter MethodChannel calls for AR recording operations.
class ArRecorderMethodChannelHandler {

    private static let channelName = "ar_recorder"

    private let interop = ARRecorderInterop.sharedInterop()
    private let cueAudioRouter = RecorderCueAudioRouter()
    private let methodChannel: FlutterMethodChannel
    private let lifecycleQueue = DispatchQueue(label: "ar.recorder.lifecycle", qos: .userInitiated)

    init(binaryMessenger: FlutterBinaryMessenger, textureRegistry: FlutterTextureRegistry) {
        self.methodChannel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: binaryMessenger)
        self.interop.configure(textureRegistry: textureRegistry)

        self.interop.onLowStorageWarning = { [weak self] in
            DispatchQueue.main.async {
                self?.methodChannel.invokeMethod("lowStorageWarning", arguments: nil)
            }
        }
        self.interop.onStorageCritical = { [weak self] in
            DispatchQueue.main.async {
                self?.methodChannel.invokeMethod("storageCritical", arguments: nil)
            }
        }

        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "initializeSession":
                self.handleInitializeSession(arguments: call.arguments, result: result)
            case "startRecording":
                self.handleStartRecording(arguments: call.arguments, result: result)
            case "pauseRecording":
                self.handlePauseRecording(result: result)
            case "resumeRecording":
                self.handleResumeRecording(result: result)
            case "cancelRecording":
                self.handleCancelRecording(result: result)
            case "stopRecording":
                self.handleStopRecording(result: result)
            case "getRecordingState":
                self.handleGetRecordingState(result: result)
            case "checkArAvailability":
                self.handleCheckArAvailability(result: result)
            case "disposeSession":
                self.handleDisposeSession(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        print("ArRecorderMethodChannelHandler initialized")
    }

    private func handleInitializeSession(arguments: Any?, result: @escaping FlutterResult) {
        UIApplication.shared.isIdleTimerDisabled = true
        let prefs = arguments as? [String: Any?]
        let response = interop.initializeSessionResponse(preferences: prefs)
        result(response)
    }

    private func handleStartRecording(arguments: Any?, result: @escaping FlutterResult) {
        let config = ARFRecordingConfig.fromNativeDictionary(arguments as? [String: Any])
        runBackgroundAction(
            action: { [weak self] in self?.interop.startRecording(config: config).toDictionary() ?? ["success": false, "error": "Handler released"] },
            errorCode: "START_RECORDING_ERROR",
            errorMessage: "Failed to start recording",
            result: result
        )
    }

    private func handlePauseRecording(result: @escaping FlutterResult) {
        runBackgroundAction(
            action: { [weak self] in self?.interop.pauseRecording().toDictionary() ?? ["success": false, "error": "Handler released"] },
            errorCode: "PAUSE_RECORDING_ERROR",
            errorMessage: "Failed to pause recording",
            result: result
        )
    }

    private func handleResumeRecording(result: @escaping FlutterResult) {
        runBackgroundAction(
            action: { [weak self] in self?.interop.resumeRecording().toDictionary() ?? ["success": false, "error": "Handler released"] },
            errorCode: "RESUME_RECORDING_ERROR",
            errorMessage: "Failed to resume recording",
            result: result
        )
    }

    private func handleCancelRecording(result: @escaping FlutterResult) {
        runBackgroundAction(
            action: { [weak self] in self?.interop.cancelRecording().toDictionary() ?? ["success": false, "error": "Handler released"] },
            errorCode: "CANCEL_RECORDING_ERROR",
            errorMessage: "Failed to cancel recording",
            result: result
        )
    }

    private func handleStopRecording(result: @escaping FlutterResult) {
        runBackgroundAction(
            action: { [weak self] in self?.interop.stopRecording().toDictionary() ?? ["success": false, "error": "Handler released"] },
            errorCode: "STOP_RECORDING_ERROR",
            errorMessage: "Failed to stop recording",
            result: result
        )
    }

    private func handleGetRecordingState(result: @escaping FlutterResult) {
        let response = interop.getRecordingState().toDictionary()
        result(response)
    }

    private func handleCheckArAvailability(result: @escaping FlutterResult) {
        let response = interop.checkArAvailability().toDictionary()
        result(response)
    }

    private func handleDisposeSession(result: @escaping FlutterResult) {
        lifecycleQueue.async { [weak self] in
            self?.interop.disposeSession()
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
                result(["success": true])
            }
        }
    }

    private func runBackgroundAction(
        action: @escaping () -> [String: Any?],
        errorCode: String,
        errorMessage: String,
        result: @escaping FlutterResult
    ) {
        lifecycleQueue.async {
            let response = action()
            DispatchQueue.main.async {
                result(response)
            }
        }
    }
}

private final class RecorderCueAudioRouter {
    private let session = AVAudioSession.sharedInstance()
    private var storedCategory: AVAudioSession.Category?
    private var storedMode: AVAudioSession.Mode?
    private var storedOptions: AVAudioSession.CategoryOptions?
    private var hasStoredPreviousConfiguration = false

    func prepareSpeakerRoute() throws {
        if !hasStoredPreviousConfiguration {
            storedCategory = session.category
            storedMode = session.mode
            storedOptions = session.categoryOptions
            hasStoredPreviousConfiguration = true
        }

        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
        try session.overrideOutputAudioPort(.speaker)
    }

    /// Ensures audio session is configured for recording input without
    /// overriding the output port.  Returns false when no input is available
    /// (e.g. the device has no microphone).
    func ensureRecordingSession() -> Bool {
        do {
            if !hasStoredPreviousConfiguration {
                storedCategory = session.category
                storedMode = session.mode
                storedOptions = session.categoryOptions
                hasStoredPreviousConfiguration = true
            }
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("RecorderCueAudioRouter: ensureRecordingSession failed – \(error)")
            return false
        }
        return session.isInputAvailable
    }

    func releaseSpeakerRoute() throws {
        guard hasStoredPreviousConfiguration else { return }

        try? session.overrideOutputAudioPort(.none)
        if let storedCategory, let storedMode, let storedOptions {
            try session.setCategory(storedCategory, mode: storedMode, options: storedOptions)
            try session.setActive(true)
        }

        hasStoredPreviousConfiguration = false
        storedCategory = nil
        storedMode = nil
        storedOptions = nil
    }
}
