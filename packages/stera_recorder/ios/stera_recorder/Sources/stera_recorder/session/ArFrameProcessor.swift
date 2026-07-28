import Foundation
import ARKit

protocol ArFrameProcessor {
    func resetAllocationCounters()
    func prepareForRecording()
    func getPointCloudBufferAllocations() -> Int
    func getDepthBufferAllocations() -> Int
    func getPointCloudAcquireCount() -> Int
    func getPointCloudReleaseCount() -> Int
    func getDepthImageAcquireCount() -> Int
    func getDepthImageCloseCount() -> Int
    func extractPose(camera: ARCamera) -> [Float]
    func extractTrackingState(camera: ARCamera) -> String
    func extractPointCloudFrame(frame: ARFrame, timestampNs: Int64) -> PointCloudFrameData?
    func extractDepthImage(frame: ARFrame) -> DepthFrameData?
    func extractMeshData(anchors: [ARAnchor], timestampNs: Int64) -> MeshFrameData?
    func getMeshBufferAllocations() -> Int
    func extractIntrinsics(camera: ARCamera, pixelBuffer: CVPixelBuffer) -> [String: Any]
    func extractDepthIntrinsics(camera: ARCamera, depthWidth: Int, depthHeight: Int) -> [String: Any]?
}
