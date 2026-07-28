import Foundation

protocol FrameSampler {
    func configure(targetFps: Int)
    func shouldEncodeFrame(timestampNs: Int64) -> Bool
    func recordTrackingPauseOffset(offsetNs: Int64)
    func reset()
    func getDriftStats() -> [String: Any]
}
