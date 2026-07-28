import Foundation
import ARKit

class FrameProcessingPipeline {

    struct TrackingTransitionResult {
        let trackingPausedAtNs: Int64
        let trackingPauseCount: Int
        let trackingPauseTotalOffsetNs: Int64
        let wasTrackingInPreviousFrame: Bool
        let depthCadenceResetCount: Int
    }

    func evaluateTrackingTransition(
        timestampNs: Int64,
        trackingState: ARCamera.TrackingState,
        trackingPausedAtNs: Int64,
        trackingPauseCount: Int,
        trackingPauseTotalOffsetNs: Int64,
        wasTrackingInPreviousFrame: Bool,
        depthCadenceResetCount: Int,
        onTrackingPauseOffset: (Int64) -> Void
    ) -> TrackingTransitionResult {
        var pausedAt = trackingPausedAtNs
        var pauseCount = trackingPauseCount
        var pauseOffsetNs = trackingPauseTotalOffsetNs
        var cadenceResetCount = depthCadenceResetCount

        let isTracking: Bool
        switch trackingState {
        case .normal:
            isTracking = true
        default:
            isTracking = false
        }

        if !isTracking {
            if pausedAt == Int64.min {
                pausedAt = timestampNs
                pauseCount += 1
            }
        } else if pausedAt != Int64.min {
            let offsetNs = max(timestampNs - pausedAt, 0)
            pauseOffsetNs += offsetNs
            onTrackingPauseOffset(offsetNs)
            pausedAt = Int64.min
        }

        if isTracking && !wasTrackingInPreviousFrame {
            cadenceResetCount += 1
        }

        return TrackingTransitionResult(
            trackingPausedAtNs: pausedAt,
            trackingPauseCount: pauseCount,
            trackingPauseTotalOffsetNs: pauseOffsetNs,
            wasTrackingInPreviousFrame: isTracking,
            depthCadenceResetCount: cadenceResetCount
        )
    }

    func shouldProcess(isPaused: Bool, frameTimestamp: TimeInterval) -> Bool {
        return !isPaused && frameTimestamp > 0
    }
}
