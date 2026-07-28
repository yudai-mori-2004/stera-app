import Foundation
import ARKit
import Flutter

@objcMembers
@objc(ARFRecordingConfig)
final class ARFRecordingConfig: NSObject {
    var recordImu: Bool = true
    var recordDepth: Bool = true
    var recordPointCloud: Bool = true
    var recordMesh: Bool = true
    var recordRgb: Bool = true
    var rgbHz: Int = 15
    var depthHz: Int = 15
    var pointCloudHz: Int = 15
    var imuHz: Int = 100
    var rgbVideoHeight: Int = 720
    var autoFocus: Bool = true
    var autoExposure: Bool = true
    var arkitFps: Int = 60
    var enableInertialDerived: Bool = false
    func toNativeConfig() -> RecordingConfig {
        RecordingConfig(
            recordImu: recordImu,
            recordDepth: recordDepth,
            recordPointCloud: recordPointCloud,
            recordMesh: recordMesh,
            recordRgb: recordRgb,
            rgbHz: rgbHz,
            depthHz: depthHz,
            pointCloudHz: pointCloudHz,
            imuHz: imuHz,
            rgbVideoHeight: RecordingConfig.sanitizedRgbVideoHeight(rgbVideoHeight),
            autoFocus: autoFocus,
            autoExposure: autoExposure,
            arkitFps: arkitFps,
            enableInertialDerived: enableInertialDerived
        )
    }

    func toDictionary() -> [String: Any] {
        [
            "recordImu": recordImu,
            "recordDepth": recordDepth,
            "recordPointCloud": recordPointCloud,
            "recordMesh": recordMesh,
            "recordRgb": recordRgb,
            "rgbHz": rgbHz,
            "depthHz": depthHz,
            "pointCloudHz": pointCloudHz,
            "imuHz": imuHz,
            "rgbVideoHeight": rgbVideoHeight,
            "autoFocus": autoFocus,
            "autoExposure": autoExposure,
            "arkitFps": arkitFps,
            "enableInertialDerived": enableInertialDerived,
        ]
    }

    static func fromNativeDictionary(_ dict: [String: Any]?) -> ARFRecordingConfig {
        let config = ARFRecordingConfig()
        config.recordImu = dict?["recordImu"] as? Bool ?? true
        config.recordDepth = dict?["recordDepth"] as? Bool ?? true
        config.recordPointCloud = dict?["recordPointCloud"] as? Bool ?? true
        config.recordMesh = dict?["recordMesh"] as? Bool ?? true
        config.recordRgb = dict?["recordRgb"] as? Bool ?? true
        config.rgbHz = RecordingConfig.sanitizedSpatialHz(dict?["rgbHz"] as? Int ?? 15)
        config.depthHz = RecordingConfig.sanitizedSpatialHz(dict?["depthHz"] as? Int ?? 15)
        config.pointCloudHz = RecordingConfig.sanitizedSpatialHz(dict?["pointCloudHz"] as? Int ?? 15)
        config.imuHz = RecordingConfig.sanitizedImuHz(dict?["imuHz"] as? Int ?? 100)
        config.rgbVideoHeight = RecordingConfig.sanitizedRgbVideoHeight(dict?["rgbVideoHeight"] as? Int ?? 720)
        config.autoFocus = dict?["autoFocus"] as? Bool ?? true
        config.autoExposure = dict?["autoExposure"] as? Bool ?? true
        config.arkitFps = RecordingConfig.sanitizedArkitFps(dict?["arkitFps"] as? Int ?? 60)
        config.enableInertialDerived = dict?["enableInertialDerived"] as? Bool ?? false
        return config
    }
}

@objcMembers
@objc(ARFRecorderResult)
final class ARFRecorderResult: NSObject {
    var success: Bool = false
    var supported: Bool = false
    var state: String = ""
    var trackingState: String = ""
    var errorMessage: String = ""
    var outputDirectory: String = ""
    var cameraResolution: String = ""
    var recordingResolution: String = ""
    var lowQualityReason: String = ""
    var depthSupported: Bool = false
    var meshSupported: Bool = false
    var isRecording: Bool = false
    var isPaused: Bool = false
    var isFinalizationInProgress: Bool = false
    var isLowQualityMode: Bool = false
    var textureId: Int64 = -1
    var frameCount: Int64 = -1
    var previewWidth: Int64 = -1
    var previewHeight: Int64 = -1
    var recordingDurationMs: Int64 = -1
    var durationSeconds: Double = -1
    var framesRecorded: Int64 = -1
    var imuSamples: Int64 = -1
    var recordingHz: Int64 = 15

    static func fromNativeDictionary(
        _ native: [String: Any?],
        fallbackRecordingHz: Int
    ) -> ARFRecorderResult {
        let result = ARFRecorderResult()
        result.success = native["success"] as? Bool ?? false
        result.supported = native["supported"] as? Bool ?? false
        result.state = native["state"] as? String ?? ""
        result.trackingState = native["trackingState"] as? String ?? ""
        result.errorMessage = native["error"] as? String ?? ""
        result.outputDirectory = native["outputDirectory"] as? String ?? ""
        result.cameraResolution = native["cameraResolution"] as? String ?? ""
        result.recordingResolution = native["recordingResolution"] as? String ?? ""
        result.lowQualityReason = native["lowQualityReason"] as? String ?? ""
        result.depthSupported = native["depthSupported"] as? Bool ?? false
        result.meshSupported = native["meshSupported"] as? Bool ?? false
        result.isRecording = native["isRecording"] as? Bool ?? false
        result.isPaused = native["isPaused"] as? Bool ?? false
        result.isFinalizationInProgress = native["isFinalizationInProgress"] as? Bool ?? false
        result.isLowQualityMode = native["isLowQualityMode"] as? Bool ?? false
        result.textureId = int64Value(native["textureId"])
        result.frameCount = int64Value(native["frameCount"])
        result.previewWidth = int64Value(native["previewWidth"])
        result.previewHeight = int64Value(native["previewHeight"])
        result.recordingDurationMs = int64Value(native["recordingDuration"])
        result.durationSeconds = (native["durationSeconds"] as? NSNumber)?.doubleValue ?? (native["durationSeconds"] as? Double ?? -1)
        result.framesRecorded = int64Value(native["framesRecorded"])
        result.imuSamples = int64Value(native["imuSamples"])
        result.recordingHz = int64Value(native["recordingHz"], fallback: Int64(fallbackRecordingHz))
        return result
    }

    func toDictionary() -> [String: Any?] {
        [
            "success": success,
            "supported": supported,
            "state": optionalStringValue(state),
            "trackingState": optionalStringValue(trackingState),
            "error": optionalStringValue(errorMessage),
            "outputDirectory": optionalStringValue(outputDirectory),
            "cameraResolution": optionalStringValue(cameraResolution),
            "recordingResolution": optionalStringValue(recordingResolution),
            "lowQualityReason": optionalStringValue(lowQualityReason),
            "depthSupported": depthSupported,
            "meshSupported": meshSupported,
            "isRecording": isRecording,
            "isPaused": isPaused,
            "isFinalizationInProgress": isFinalizationInProgress,
            "isLowQualityMode": isLowQualityMode,
            "textureId": textureId >= 0 ? textureId : nil,
            "frameCount": frameCount >= 0 ? frameCount : nil,
            "previewWidth": previewWidth >= 0 ? previewWidth : nil,
            "previewHeight": previewHeight >= 0 ? previewHeight : nil,
            "recordingDuration": recordingDurationMs >= 0 ? recordingDurationMs : nil,
            "durationSeconds": durationSeconds >= 0 ? durationSeconds : nil,
            "framesRecorded": framesRecorded >= 0 ? framesRecorded : nil,
            "imuSamples": imuSamples >= 0 ? imuSamples : nil,
            "recordingHz": Int(recordingHz)
        ]
    }

    private static func int64Value(_ value: Any?, fallback: Int64 = -1) -> Int64 {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return fallback
    }

    private func optionalStringValue(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

private final class ArRecorderSharedController {
    static let shared = ArRecorderSharedController()

    private var arRecorder: ArRecorder?
    private var currentRecordingHz = 15

    var onLowStorageWarning: (() -> Void)? {
        didSet { arRecorder?.onLowStorageWarning = onLowStorageWarning }
    }

    var onStorageCritical: (() -> Void)? {
        didSet { arRecorder?.onStorageCritical = onStorageCritical }
    }

    private init() {}

    func configure(textureRegistry: FlutterTextureRegistry) {
        if arRecorder == nil {
            let recorder = ArRecorderImpl(textureRegistry: textureRegistry)
            recorder.onLowStorageWarning = onLowStorageWarning
            recorder.onStorageCritical = onStorageCritical
            arRecorder = recorder
        }
    }

    func initializeSession(preferences: [String: Any?]? = nil) -> [String: Any?] {
        guard let recorder = arRecorder else {
            return unavailableRecorderResponse()
        }
        let response = recorder.initializeSession(preferences: preferences)
        return withRecordingHz(response, recordingHz: currentRecordingHz)
    }

    func startRecording(config: ARFRecordingConfig) -> ARFRecorderResult {
        let nativeConfig = config.toNativeConfig()
        currentRecordingHz = nativeConfig.maxSpatialHz
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        let response = recorder.startRecording(config: nativeConfig)
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(response, recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func pauseRecording() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(recorder.pauseRecording(), recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func resumeRecording() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(recorder.resumeRecording(), recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func cancelRecording() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(recorder.cancelRecording(), recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func stopRecording() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(recorder.stopRecording(), recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func getRecordingState() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            return ARFRecorderResult.fromNativeDictionary(
                unavailableRecorderStateResponse(),
                fallbackRecordingHz: currentRecordingHz
            )
        }
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(recorder.getRecordingState(), recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func checkArAvailability() -> ARFRecorderResult {
        guard let recorder = arRecorder else {
            let result = ARFRecorderResult()
            result.supported = ARWorldTrackingConfiguration.isSupported
            result.success = true
            result.recordingHz = Int64(currentRecordingHz)
            return result
        }
        var response = recorder.checkArAvailability()
        response["success"] = true
        return ARFRecorderResult.fromNativeDictionary(
            withRecordingHz(response, recordingHz: currentRecordingHz),
            fallbackRecordingHz: currentRecordingHz
        )
    }

    func disposeSession() {
        arRecorder?.disposeSession()
    }

    func currentSessionDirectory() -> URL? {
        return arRecorder?.currentSessionDirectory()
    }

    private func unavailableRecorderResponse() -> [String: Any?] {
        [
            "success": false,
            "state": ArRecordingState.uninitialized.rawValue,
            "error": "AR recorder not configured"
        ]
    }

    private func unavailableRecorderStateResponse() -> [String: Any?] {
        [
            "success": false,
            "state": ArRecordingState.uninitialized.rawValue,
            "trackingState": "STOPPED",
            "isRecording": false,
            "isPaused": false,
            "depthSupported": false,
            "meshSupported": false,
            "isFinalizationInProgress": false,
            "error": "AR recorder not configured"
        ]
    }

    private func withRecordingHz(
        _ response: [String: Any?],
        recordingHz: Int
    ) -> [String: Any?] {
        var enriched = response
        enriched["recordingHz"] = recordingHz
        return enriched
    }
}

@objcMembers
@objc(ARRecorderInterop)
final class ARRecorderInterop: NSObject {
    private static let sharedInstance = ARRecorderInterop()

    @objc(sharedInterop)
    class func sharedInterop() -> ARRecorderInterop {
        sharedInstance
    }

    func configure(textureRegistry: FlutterTextureRegistry) {
        ArRecorderSharedController.shared.configure(textureRegistry: textureRegistry)
    }

    var onLowStorageWarning: (() -> Void)? {
        get { ArRecorderSharedController.shared.onLowStorageWarning }
        set { ArRecorderSharedController.shared.onLowStorageWarning = newValue }
    }

    var onStorageCritical: (() -> Void)? {
        get { ArRecorderSharedController.shared.onStorageCritical }
        set { ArRecorderSharedController.shared.onStorageCritical = newValue }
    }

    func initializeSessionResponse(preferences: [String: Any?]? = nil) -> [String: Any?] {
        ArRecorderSharedController.shared.initializeSession(preferences: preferences)
    }

    @objc(startRecordingWithConfig:)
    func startRecording(config: ARFRecordingConfig) -> ARFRecorderResult {
        ArRecorderSharedController.shared.startRecording(config: config)
    }

    @objc(pauseRecording)
    func pauseRecording() -> ARFRecorderResult {
        ArRecorderSharedController.shared.pauseRecording()
    }

    @objc(resumeRecording)
    func resumeRecording() -> ARFRecorderResult {
        ArRecorderSharedController.shared.resumeRecording()
    }

    @objc(cancelRecording)
    func cancelRecording() -> ARFRecorderResult {
        ArRecorderSharedController.shared.cancelRecording()
    }

    @objc(stopRecording)
    func stopRecording() -> ARFRecorderResult {
        ArRecorderSharedController.shared.stopRecording()
    }

    @objc(getRecordingState)
    func getRecordingState() -> ARFRecorderResult {
        ArRecorderSharedController.shared.getRecordingState()
    }

    @objc(checkArAvailability)
    func checkArAvailability() -> ARFRecorderResult {
        ArRecorderSharedController.shared.checkArAvailability()
    }

    func disposeSession() {
        ArRecorderSharedController.shared.disposeSession()
    }

}
