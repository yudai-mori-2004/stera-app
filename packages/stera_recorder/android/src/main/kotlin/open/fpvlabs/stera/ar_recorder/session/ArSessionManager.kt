package open.fpvlabs.stera.ar_recorder.session

import android.app.Activity
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Session
import com.google.ar.core.TrackingState

interface ArSessionManager {
    val session: Session?
    val isDepthSupported: Boolean
    val isSessionReady: Boolean
    val selectedCameraResolution: String
    val selectedFocusMode: String

    fun checkAvailability(callback: (ArCoreApk.Availability) -> Unit)
    fun createSession(activity: Activity)
    fun resume()
    fun pause()
    fun updateTrackingState(trackingState: TrackingState?): Boolean
    fun hasStableTrackingFor(minDurationMs: Long): Boolean
    fun getTrackingStateString(trackingState: TrackingState?): String
    fun release()
}
