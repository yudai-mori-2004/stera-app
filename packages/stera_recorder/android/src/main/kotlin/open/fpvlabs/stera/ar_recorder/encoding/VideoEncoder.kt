package open.fpvlabs.stera.ar_recorder.encoding

import java.io.File

data class EncoderSetupResult(
    val chosenBitrate: Int,
    val chosenFps: Int,
    val chosenWidth: Int,
    val chosenHeight: Int
)

interface VideoEncoder {
    val actualVideoWidth: Int
    val actualVideoHeight: Int
    val activeVideoBitrate: Int

    fun setup(
        outputFile: File,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int,
        fallbackBitrate: Int,
        iFrameIntervalSeconds: Int
    ): EncoderSetupResult?

    fun ensureEncoderSurfaceReady(eglManager: EglManager): Boolean

    fun applyBitrate(newBitrate: Int): Boolean

    fun drain(
        endOfStream: Boolean,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    )

    fun finalizeStream(
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    )

    fun release()
}
