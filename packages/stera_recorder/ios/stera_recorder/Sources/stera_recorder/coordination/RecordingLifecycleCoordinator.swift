import Foundation

class RecordingLifecycleCoordinator {

    struct PauseResult {
        let isPaused: Bool
        let pauseStartedAtMs: Int64
        let nextState: ArRecordingState
    }

    struct ResumeResult {
        let isPaused: Bool
        let pauseStartedAtMs: Int64
        let totalPausedDurationMs: Int64
        let nextState: ArRecordingState
    }

    struct CancelResult {
        let isRecording: Bool
        let isPaused: Bool
        let pauseStartedAtMs: Int64
        let totalPausedDurationMs: Int64
        let nextState: ArRecordingState
    }

    func pauseRecording(nowMs: Int64) -> PauseResult {
        return PauseResult(
            isPaused: true,
            pauseStartedAtMs: nowMs,
            nextState: .paused
        )
    }

    func resumeRecording(
        nowMs: Int64,
        pauseStartedAtMs: Int64,
        totalPausedDurationMs: Int64
    ) -> ResumeResult {
        let updatedPausedDurationMs: Int64
        if pauseStartedAtMs > 0 {
            updatedPausedDurationMs = totalPausedDurationMs + max(nowMs - pauseStartedAtMs, 0)
        } else {
            updatedPausedDurationMs = totalPausedDurationMs
        }
        return ResumeResult(
            isPaused: false,
            pauseStartedAtMs: 0,
            totalPausedDurationMs: updatedPausedDurationMs,
            nextState: .recording
        )
    }

    func cancelRecording() -> CancelResult {
        return CancelResult(
            isRecording: false,
            isPaused: false,
            pauseStartedAtMs: 0,
            totalPausedDurationMs: 0,
            nextState: .cancelling
        )
    }
}
