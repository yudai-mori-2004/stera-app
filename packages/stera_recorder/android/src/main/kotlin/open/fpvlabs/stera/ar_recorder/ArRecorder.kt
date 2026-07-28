package open.fpvlabs.stera.ar_recorder

/**
 * Interface for AR recording operations using ARCore.
 * Captures synchronized RGB video, IMU data, camera poses, point clouds,
 * and depth data (if supported).
 */
interface ArRecorder {

    /**
     * Initializes the ARCore session and prepares for recording.
     * Must be called before startRecording().
     * 
     * @return Map containing initialization result:
     *         - success (Boolean): Whether initialization succeeded
     *         - state (String): Current recording state
     *         - depthSupported (Boolean): Whether depth recording is available
     *         - textureId (Int?): Texture ID for preview (null if unavailable)
     *         - error (String?): Error message if initialization failed
     */
    fun initializeSession(arguments: Any? = null): Map<String, Any?>

    /**
     * Starts recording AR data.
     * Only succeeds if the session is in READY state and tracking is stable.
     * 
     * @return Map containing start result:
     *         - success (Boolean): Whether recording started
     *         - state (String): Current recording state
     *         - outputDirectory (String?): Path to the recording directory
     *         - error (String?): Error message if start failed
     */
    fun startRecording(arguments: Any? = null): Map<String, Any?>

    /**
     * Pauses recording while keeping the same session active.
     */
    fun pauseRecording(): Map<String, Any?>

    /**
     * Resumes a previously paused recording.
     */
    fun resumeRecording(): Map<String, Any?>

    /**
     * Cancels the current recording and deletes session output.
     */
    fun cancelRecording(): Map<String, Any?>

    /**
     * Stops recording and finalizes all output files.
     * 
     * @return Map containing stop result:
     *         - success (Boolean): Whether recording stopped successfully
     *         - state (String): Current recording state
     *         - outputDirectory (String?): Path to the final recording directory
     *         - error (String?): Error message if stop failed
     */
    fun stopRecording(): Map<String, Any?>

    /**
     * Gets the current recording state and session information.
     * 
     * @return Map containing:
     *         - state (String): Current recording state
     *         - trackingState (String): ARCore tracking state
     *         - isRecording (Boolean): Whether currently recording
     *         - depthSupported (Boolean): Whether depth is available
     *         - recordingDuration (Long?): Duration in milliseconds (if recording)
     *         - frameCount (Int?): Number of frames captured (if recording)
     */
    fun getRecordingState(): Map<String, Any?>

    /**
     * Checks if ARCore is supported on this device.
     * Uses the synchronous (cached) variant of checkAvailability.
     *
     * @return Map containing:
     *         - supported (Boolean): Whether ARCore is supported
     */
    fun checkArAvailability(): Map<String, Any?>

    /**
     * Disposes the ARCore session and releases all resources.
     * Should be called when the recorder is no longer needed.
     */
    fun disposeSession()
}
