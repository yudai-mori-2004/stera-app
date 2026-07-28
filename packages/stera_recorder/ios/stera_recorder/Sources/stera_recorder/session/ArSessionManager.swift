import Foundation
import ARKit

protocol ArSessionManagerDelegate: AnyObject {
    func arSessionManager(_ manager: ArSessionManager, didUpdateFrame frame: ARFrame)

    /// Fired for any anchor add/update/remove.
    func arSessionManager(_ manager: ArSessionManager, didAddAnchors anchors: [ARAnchor])
    func arSessionManager(_ manager: ArSessionManager, didUpdateAnchors anchors: [ARAnchor])
    func arSessionManager(_ manager: ArSessionManager, didRemoveAnchors anchors: [ARAnchor])
}

// Default no-op implementations so existing conformers (e.g. tests) don't
// need to implement anchor hooks unless they care.
extension ArSessionManagerDelegate {
    func arSessionManager(_ manager: ArSessionManager, didAddAnchors anchors: [ARAnchor]) {}
    func arSessionManager(_ manager: ArSessionManager, didUpdateAnchors anchors: [ARAnchor]) {}
    func arSessionManager(_ manager: ArSessionManager, didRemoveAnchors anchors: [ARAnchor]) {}
}

protocol ArSessionManager: AnyObject {
    var session: ARSession? { get }
    var isDepthSupported: Bool { get }
    var isMeshSupported: Bool { get }
    var isSessionReady: Bool { get }
    var selectedCameraResolution: String { get }
    var activeArkitFps: Int { get }
    var delegate: ArSessionManagerDelegate? { get set }

    func checkAvailability() -> Bool
    func createSession(maxCaptureHeight: Int, autoFocus: Bool, autoExposure: Bool, arkitFps: Int)
    func resume()
    func pause()

    func updateTrackingState(_ trackingState: ARCamera.TrackingState) -> Bool
    func hasStableTrackingFor(minDurationMs: Int64) -> Bool
    func getTrackingStateString(_ trackingState: ARCamera.TrackingState) -> String
    func releaseSession()
}
