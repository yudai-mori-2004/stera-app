import Foundation

class RecordingStateManager {
    func canStart(currentState: ArRecordingState) -> Bool {
        return currentState == .ready
    }

    func canStop(currentState: ArRecordingState) -> Bool {
        return currentState == .recording || currentState == .paused
    }

    func canPause(currentState: ArRecordingState) -> Bool {
        return currentState == .recording
    }

    func canResume(currentState: ArRecordingState) -> Bool {
        return currentState == .paused
    }

    func canCancel(currentState: ArRecordingState) -> Bool {
        return currentState == .recording || currentState == .paused
    }
}
