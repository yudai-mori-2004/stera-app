import Foundation
import ARKit
import AVFoundation

/// Manages ARKit session lifecycle and configuration.
/// Conforms to ARSessionDelegate to receive frame updates via delegate push model.
class ArSessionManagerImpl: NSObject, ArSessionManager, ARSessionDelegate {

    private static let minStableTrackingFrames = 10
    private static let skipInitialFrames = 30

    private(set) var session: ARSession?
    private(set) var isDepthSupported: Bool = false
    private(set) var isMeshSupported: Bool = false
    private(set) var isSessionReady: Bool = false
    private(set) var selectedCameraResolution: String = "unknown"

    weak var delegate: ArSessionManagerDelegate?

    private var captureHeightLimit: CGFloat = 720
    private var autoFocusEnabled: Bool = true
    private var autoExposureEnabled: Bool = true
    private var requestedArkitFps: Int = 60
    private(set) var activeArkitFps: Int = 0

    private var skippedFrames: Int = 0
    private var consecutiveTrackingFrames: Int = 0
    private var stableTrackingSinceMs: Int64?

    func checkAvailability() -> Bool {
        return ARWorldTrackingConfiguration.isSupported
    }

    func createSession(maxCaptureHeight: Int, autoFocus: Bool, autoExposure: Bool, arkitFps: Int) {
        if session != nil {
            print("ARKit session already exists")
            return
        }

        let capped = max(360, min(maxCaptureHeight, 2160))
        captureHeightLimit = CGFloat(capped)
        autoFocusEnabled = autoFocus
        autoExposureEnabled = autoExposure
        requestedArkitFps = arkitFps

        let arSession = ARSession()
        arSession.delegate = self
        session = arSession

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]

        // Check LiDAR/depth support
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            isDepthSupported = true
            print("Depth mode enabled (LiDAR)")
        } else {
            isDepthSupported = false
            print("Depth mode not supported on this device")
        }

        // Check mesh reconstruction support (LiDAR)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            isMeshSupported = true
            print("Mesh reconstruction enabled (LiDAR)")
        } else {
            isMeshSupported = false
            print("Mesh reconstruction not supported on this device")
        }

        config.isAutoFocusEnabled = autoFocusEnabled
        print("Auto focus \(autoFocusEnabled ? "enabled" : "disabled (fixed focus)")")

        if let format = preferredVideoFormat() {
            config.videoFormat = format
            let size = format.imageResolution
            selectedCameraResolution = "\(Int(size.width))x\(Int(size.height))"
            activeArkitFps = Int(format.framesPerSecond)
            print("Selected ARKit video format (cap=\(Int(captureHeightLimit))p, requestedFps=\(requestedArkitFps)): \(Int(size.width))x\(Int(size.height))@\(activeArkitFps)fps")
        } else if let fallback = ARWorldTrackingConfiguration.supportedVideoFormats.first {
            let size = fallback.imageResolution
            selectedCameraResolution = "\(Int(size.width))x\(Int(size.height))"
            activeArkitFps = Int(fallback.framesPerSecond)
            print("No format within height cap, using default: \(Int(size.width))x\(Int(size.height))@\(activeArkitFps)fps")
        }

        arSession.run(config)
        applyExposurePreferenceAfterSettle()
        print("ARKit session created and running")
    }

    /// ARKit boots the primary camera in continuous auto-exposure and re-asserts
    /// it on every `ARSession.run(...)`. When the user opts out of auto-exposure
    /// we wait for AE to converge, then lock the configurable primary capture
    /// device (iOS 16+) so brightness stays constant for the rest of the take.
    /// No-op when auto-exposure is enabled, the OS is < iOS 16, or ARKit doesn't
    /// vend a configurable device. Re-run on `resume()` because each run resets it.
    private func applyExposurePreferenceAfterSettle() {
        guard !autoExposureEnabled else { return }
        guard #available(iOS 16.0, *) else {
            print("Auto exposure lock requested but unavailable (<iOS 16) — leaving auto-exposure on")
            return
        }
        let runningSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.session === runningSession, !self.autoExposureEnabled else { return }
            guard let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else {
                print("Auto exposure lock: no configurable capture device available")
                return
            }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                    print("Auto exposure disabled — exposure locked on primary camera")
                } else {
                    print("Auto exposure lock: .locked mode unsupported on primary camera")
                }
                device.unlockForConfiguration()
            } catch {
                print("Auto exposure lock failed: \(error.localizedDescription)")
            }
        }
    }

    /// Picks a video format that (a) fits the capture height cap and (b) matches
    /// `requestedArkitFps` when possible. Falls back to the largest-area format
    /// at the highest available fps within the cap.
    ///
    /// When the cap admits 4K (≥ 2160p) we prefer ARKit's dedicated
    /// `recommendedVideoFormatFor4KResolution` (3840×2160 @ 30 fps). It returns
    /// nil when the device/configuration can't deliver 4K, in which case we fall
    /// through to the largest-within-cap selection (typically 1080p) — the
    /// caller reports the actual resolution back to Dart so the UI stays honest.
    private func preferredVideoFormat() -> ARConfiguration.VideoFormat? {
        if captureHeightLimit >= 2160, #available(iOS 16.0, *),
           let fourK = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
            return fourK
        }

        let withinCap = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.imageResolution.height <= captureHeightLimit }
        if withinCap.isEmpty { return nil }

        let largestArea = withinCap
            .map { $0.imageResolution.width * $0.imageResolution.height }
            .max() ?? 0
        let largest = withinCap.filter { $0.imageResolution.width * $0.imageResolution.height == largestArea }

        if let match = largest.first(where: { Int($0.framesPerSecond) == requestedArkitFps }) {
            return match
        }
        return largest.max(by: { $0.framesPerSecond < $1.framesPerSecond })
            ?? withinCap.max(by: { $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height })
    }

    func resume() {
        guard let arSession = session else { return }
        let config = makeConfig()
        arSession.run(config)
        applyExposurePreferenceAfterSettle()
        skippedFrames = 0
        consecutiveTrackingFrames = 0
        isSessionReady = false
        print("ARKit session resumed")
    }

    /// Builds an `ARWorldTrackingConfiguration` that mirrors the active
    /// session's settings. Used by `resume()`.
    private func makeConfig() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        config.isAutoFocusEnabled = autoFocusEnabled
        if isDepthSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        if isMeshSupported && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if let format = preferredVideoFormat() {
            config.videoFormat = format
            activeArkitFps = Int(format.framesPerSecond)
        }
        return config
    }

    func pause() {
        session?.pause()
        print("ARKit session paused")
    }

    func updateTrackingState(_ trackingState: ARCamera.TrackingState) -> Bool {
        let isTracking: Bool
        switch trackingState {
        case .normal:
            isTracking = true
        default:
            isTracking = false
        }

        if !isTracking {
            consecutiveTrackingFrames = 0
            isSessionReady = false
            stableTrackingSinceMs = nil
            return false
        }

        if skippedFrames < Self.skipInitialFrames {
            skippedFrames += 1
            return false
        }

        consecutiveTrackingFrames += 1
        let wasReady = isSessionReady
        isSessionReady = consecutiveTrackingFrames >= Self.minStableTrackingFrames
        if !wasReady && isSessionReady {
            stableTrackingSinceMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        }
        return isSessionReady
    }

    func hasStableTrackingFor(minDurationMs: Int64) -> Bool {
        guard isSessionReady, let since = stableTrackingSinceMs else { return false }
        return Int64(ProcessInfo.processInfo.systemUptime * 1000) - since >= minDurationMs
    }

    func getTrackingStateString(_ trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .normal:
            return ArTrackingState.tracking.rawValue
        case .limited:
            return ArTrackingState.paused.rawValue
        case .notAvailable:
            return ArTrackingState.stopped.rawValue
        }
    }

    func releaseSession() {
        session?.pause()
        session = nil
        isSessionReady = false
        isDepthSupported = false
        isMeshSupported = false
        skippedFrames = 0
        consecutiveTrackingFrames = 0
        stableTrackingSinceMs = nil
        selectedCameraResolution = "unknown"
        print("ARKit session released")
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        delegate?.arSessionManager(self, didUpdateFrame: frame)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        delegate?.arSessionManager(self, didAddAnchors: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        delegate?.arSessionManager(self, didUpdateAnchors: anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        delegate?.arSessionManager(self, didRemoveAnchors: anchors)
    }
}
