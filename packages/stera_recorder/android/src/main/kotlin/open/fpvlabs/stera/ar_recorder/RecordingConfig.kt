package open.fpvlabs.stera.ar_recorder

/**
 * Mirrors Flutter [RecordingConfig] arguments for startRecording / session prefs.
 */
data class RecordingConfig(
    val recordImu: Boolean = true,
    val recordDepth: Boolean = true,
    val recordPointCloud: Boolean = true,
    val recordMesh: Boolean = true,
    val recordRgb: Boolean = true,
    val recordingHz: Int = 15,
    val rgbVideoHeight: Int = 720
) {
    val rgbLandscapeWidth: Int get() = if (rgbVideoHeight >= 1080) 1920 else 1280
    val rgbLandscapeHeight: Int get() = if (rgbVideoHeight >= 1080) 1080 else 720

    companion object {
        private val supportedHz = setOf(15, 30, 60)
        private val supportedRgbHeights = setOf(720, 1080)

        fun fromMap(map: Any?): RecordingConfig {
            val m = map as? Map<*, *> ?: return RecordingConfig()
            val hz = (m["recordingHz"] as? Number)?.toInt() ?: 15
            val rgbH = (m["rgbVideoHeight"] as? Number)?.toInt() ?: 720
            return RecordingConfig(
                recordImu = m["recordImu"] as? Boolean ?: true,
                recordDepth = m["recordDepth"] as? Boolean ?: true,
                recordPointCloud = m["recordPointCloud"] as? Boolean ?: true,
                recordMesh = m["recordMesh"] as? Boolean ?: true,
                recordRgb = m["recordRgb"] as? Boolean ?: true,
                recordingHz = if (hz in supportedHz) hz else 15,
                rgbVideoHeight = if (rgbH in supportedRgbHeights) rgbH else 720
            )
        }
    }
}
