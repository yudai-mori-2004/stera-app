import Foundation

/// Configuration for which data channels to record into the MCAP file.
struct RecordingConfig {
    static let supportedSpatialHz: Set<Int> = [5, 10, 15, 30, 60]
    /// 200 Hz is supported for the ARKit (wide-camera) path — the
    /// `ImuCollectorImpl` requests that update interval.
    static let supportedImuHz: Set<Int> = [50, 100, 200]
    static let supportedRgbVideoHeights: Set<Int> = [720, 1080, 2160]
    static let supportedArkitFps: Set<Int> = [30, 60]

    let recordImu: Bool
    let recordDepth: Bool
    let recordPointCloud: Bool
    let recordMesh: Bool
    let recordRgb: Bool
    let rgbHz: Int
    let depthHz: Int
    let pointCloudHz: Int
    let imuHz: Int
    /// Landscape short side: 720 or 1080.
    let rgbVideoHeight: Int
    let autoFocus: Bool
    /// When true, the camera runs continuous auto-exposure. When false, exposure
    /// is locked after it settles so brightness stays constant across the take.
    let autoExposure: Bool
    let arkitFps: Int
    let enableInertialDerived: Bool

    var rgbLandscapeWidth: Int {
        if rgbVideoHeight >= 2160 { return 3840 }
        return rgbVideoHeight >= 1080 ? 1920 : 1280
    }
    var rgbLandscapeHeight: Int {
        if rgbVideoHeight >= 2160 { return 2160 }
        return rgbVideoHeight >= 1080 ? 1080 : 720
    }

    /// True when the user requested 4K capture. ARKit locks 4K to 30 fps and
    /// requires `recommendedVideoFormatFor4KResolution` rather than the
    /// largest-area format within the height cap.
    var wantsFourK: Bool { rgbVideoHeight >= 2160 }

    /// The maximum spatial Hz across enabled channels — used for metrics/logging.
    var maxSpatialHz: Int {
        var hz = 1
        if recordRgb { hz = max(hz, rgbHz) }
        if recordDepth { hz = max(hz, depthHz) }
        if recordPointCloud { hz = max(hz, pointCloudHz) }
        return hz
    }

    static func sanitizedRgbVideoHeight(_ value: Int) -> Int {
        Self.supportedRgbVideoHeights.contains(value) ? value : 720
    }

    static func sanitizedSpatialHz(_ value: Int) -> Int {
        Self.supportedSpatialHz.contains(value) ? value : 15
    }

    static func sanitizedImuHz(_ value: Int) -> Int {
        Self.supportedImuHz.contains(value) ? value : 100
    }

    static func sanitizedArkitFps(_ value: Int) -> Int {
        Self.supportedArkitFps.contains(value) ? value : 60
    }

    static let defaultConfig = RecordingConfig(
        recordImu: true,
        recordDepth: true,
        recordPointCloud: true,
        recordMesh: true,
        recordRgb: true,
        rgbHz: 15,
        depthHz: 15,
        pointCloudHz: 15,
        imuHz: 100,
        rgbVideoHeight: 720,
        autoFocus: true,
        autoExposure: true,
        arkitFps: 60,
        enableInertialDerived: true
    )

    init(
        recordImu: Bool = true,
        recordDepth: Bool = true,
        recordPointCloud: Bool = true,
        recordMesh: Bool = true,
        recordRgb: Bool = true,
        rgbHz: Int = 15,
        depthHz: Int = 15,
        pointCloudHz: Int = 15,
        imuHz: Int = 100,
        rgbVideoHeight: Int = 720,
        autoFocus: Bool = true,
        autoExposure: Bool = true,
        arkitFps: Int = 60,
        enableInertialDerived: Bool = true
    ) {
        self.recordImu = recordImu
        self.recordDepth = recordDepth
        self.recordPointCloud = recordPointCloud
        self.recordMesh = recordMesh
        self.recordRgb = recordRgb
        self.rgbHz = Self.sanitizedSpatialHz(rgbHz)
        self.depthHz = Self.sanitizedSpatialHz(depthHz)
        self.pointCloudHz = Self.sanitizedSpatialHz(pointCloudHz)
        self.imuHz = Self.sanitizedImuHz(imuHz)
        self.rgbVideoHeight = Self.sanitizedRgbVideoHeight(rgbVideoHeight)
        self.autoFocus = autoFocus
        self.autoExposure = autoExposure
        self.arkitFps = Self.sanitizedArkitFps(arkitFps)
        self.enableInertialDerived = enableInertialDerived
    }

    init(from dict: [String: Any]?) {
        self.recordImu = dict?["recordImu"] as? Bool ?? true
        self.recordDepth = dict?["recordDepth"] as? Bool ?? true
        self.recordPointCloud = dict?["recordPointCloud"] as? Bool ?? true
        self.recordMesh = dict?["recordMesh"] as? Bool ?? true
        self.recordRgb = dict?["recordRgb"] as? Bool ?? true
        self.rgbHz = Self.sanitizedSpatialHz(dict?["rgbHz"] as? Int ?? 15)
        self.depthHz = Self.sanitizedSpatialHz(dict?["depthHz"] as? Int ?? 15)
        self.pointCloudHz = Self.sanitizedSpatialHz(dict?["pointCloudHz"] as? Int ?? 15)
        self.imuHz = Self.sanitizedImuHz(dict?["imuHz"] as? Int ?? 100)
        let requestedRgbH = dict?["rgbVideoHeight"] as? Int ?? 720
        self.rgbVideoHeight = Self.sanitizedRgbVideoHeight(requestedRgbH)
        self.autoFocus = dict?["autoFocus"] as? Bool ?? true
        self.autoExposure = dict?["autoExposure"] as? Bool ?? true
        self.arkitFps = Self.sanitizedArkitFps(dict?["arkitFps"] as? Int ?? 60)
        self.enableInertialDerived = dict?["enableInertialDerived"] as? Bool ?? true
    }
}
