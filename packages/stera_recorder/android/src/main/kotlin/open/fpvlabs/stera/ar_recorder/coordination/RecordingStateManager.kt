package open.fpvlabs.stera.ar_recorder.coordination

import open.fpvlabs.stera.ar_recorder.ArRecordingState

class RecordingStateManager {
    fun canStart(currentState: ArRecordingState): Boolean = currentState == ArRecordingState.READY
    fun canStop(currentState: ArRecordingState): Boolean =
        currentState == ArRecordingState.RECORDING || currentState == ArRecordingState.PAUSED
    fun canPause(currentState: ArRecordingState): Boolean = currentState == ArRecordingState.RECORDING
    fun canResume(currentState: ArRecordingState): Boolean = currentState == ArRecordingState.PAUSED
    fun canCancel(currentState: ArRecordingState): Boolean =
        currentState == ArRecordingState.RECORDING || currentState == ArRecordingState.PAUSED
}
