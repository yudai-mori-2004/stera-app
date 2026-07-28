package open.fpvlabs.stera.ar_recorder.session

import com.google.ar.core.Camera
import com.google.ar.core.Frame
import com.google.ar.core.TrackingState

class FrameProcessingPipeline {
    data class TrackingTransitionResult(
        val trackingPausedAtNs: Long,
        val trackingPauseCount: Int,
        val trackingPauseTotalOffsetNs: Long,
        val wasTrackingInPreviousFrame: Boolean,
        val depthCadenceResetCount: Int
    )

    fun evaluateTrackingTransition(
        timestampNs: Long,
        camera: Camera,
        trackingPausedAtNs: Long,
        trackingPauseCount: Int,
        trackingPauseTotalOffsetNs: Long,
        wasTrackingInPreviousFrame: Boolean,
        depthCadenceResetCount: Int,
        onTrackingPauseOffset: (Long) -> Unit
    ): TrackingTransitionResult {
        var pausedAt = trackingPausedAtNs
        var pauseCount = trackingPauseCount
        var pauseOffsetNs = trackingPauseTotalOffsetNs
        var cadenceResetCount = depthCadenceResetCount
        val isTracking = camera.trackingState == TrackingState.TRACKING
        if (!isTracking) {
            if (pausedAt == Long.MIN_VALUE) {
                pausedAt = timestampNs
                pauseCount++
            }
        } else if (pausedAt != Long.MIN_VALUE) {
            val offsetNs = (timestampNs - pausedAt).coerceAtLeast(0L)
            pauseOffsetNs += offsetNs
            onTrackingPauseOffset(offsetNs)
            pausedAt = Long.MIN_VALUE
        }
        if (isTracking && !wasTrackingInPreviousFrame) {
            cadenceResetCount++
        }
        return TrackingTransitionResult(
            trackingPausedAtNs = pausedAt,
            trackingPauseCount = pauseCount,
            trackingPauseTotalOffsetNs = pauseOffsetNs,
            wasTrackingInPreviousFrame = isTracking,
            depthCadenceResetCount = cadenceResetCount
        )
    }

    fun shouldProcess(isPaused: Boolean, frame: Frame): Boolean {
        return !isPaused && frame.timestamp > 0L
    }
}
