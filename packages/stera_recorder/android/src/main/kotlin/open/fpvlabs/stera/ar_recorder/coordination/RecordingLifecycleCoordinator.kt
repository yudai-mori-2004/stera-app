package open.fpvlabs.stera.ar_recorder.coordination

import open.fpvlabs.stera.ar_recorder.ArRecordingState

class RecordingLifecycleCoordinator {
    data class PauseResult(
        val isPaused: Boolean,
        val pauseStartedAtMs: Long,
        val nextState: ArRecordingState
    )

    data class ResumeResult(
        val isPaused: Boolean,
        val pauseStartedAtMs: Long,
        val totalPausedDurationMs: Long,
        val nextState: ArRecordingState
    )

    data class CancelResult(
        val isRecording: Boolean,
        val isPaused: Boolean,
        val pauseStartedAtMs: Long,
        val totalPausedDurationMs: Long,
        val nextState: ArRecordingState
    )

    fun pauseRecording(nowMs: Long): PauseResult {
        return PauseResult(
            isPaused = true,
            pauseStartedAtMs = nowMs,
            nextState = ArRecordingState.PAUSED
        )
    }

    fun resumeRecording(
        nowMs: Long,
        pauseStartedAtMs: Long,
        totalPausedDurationMs: Long
    ): ResumeResult {
        val updatedPausedDurationMs = if (pauseStartedAtMs > 0L) {
            totalPausedDurationMs + (nowMs - pauseStartedAtMs).coerceAtLeast(0L)
        } else {
            totalPausedDurationMs
        }
        return ResumeResult(
            isPaused = false,
            pauseStartedAtMs = 0L,
            totalPausedDurationMs = updatedPausedDurationMs,
            nextState = ArRecordingState.RECORDING
        )
    }

    fun cancelRecording(): CancelResult {
        return CancelResult(
            isRecording = false,
            isPaused = false,
            pauseStartedAtMs = 0L,
            totalPausedDurationMs = 0L,
            nextState = ArRecordingState.CANCELLING
        )
    }
}
