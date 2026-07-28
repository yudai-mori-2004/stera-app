/// Enumeration of AR recorder states matching native side.
enum ArRecorderState {
  uninitialized,
  initializing,
  ready,
  recording,
  paused,
  cancelling,
  stopping,
  error,
  disposed,
}
