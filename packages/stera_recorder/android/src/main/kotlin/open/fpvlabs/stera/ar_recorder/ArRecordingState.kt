package open.fpvlabs.stera.ar_recorder

/**
 * Enumeration of possible states for the AR recording session.
 */
enum class ArRecordingState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    RECORDING,
    PAUSED,
    STOPPING,
    CANCELLING,
    ERROR,
    DISPOSED;

    companion object {
        /**
         * Converts the enum to its string representation for Flutter serialization.
         */
        fun toString(state: ArRecordingState): String = state.name
    }
}

/**
 * Enumeration of ARCore tracking states.
 */
enum class ArTrackingState {
    TRACKING,
    PAUSED,
    STOPPED;

    companion object {
        fun fromArcoreState(state: com.google.ar.core.TrackingState?): ArTrackingState {
            return when (state) {
                com.google.ar.core.TrackingState.TRACKING -> TRACKING
                com.google.ar.core.TrackingState.PAUSED -> PAUSED
                com.google.ar.core.TrackingState.STOPPED -> STOPPED
                else -> STOPPED
            }
        }
    }
}
