package open.fpvlabs.stera.ar_recorder.encoding

import android.graphics.SurfaceTexture
import android.view.Surface

interface EglManager {
    val cameraTextureId: Int

    fun initialize(): Boolean

    fun setupPreviewSurface(surfaceTexture: SurfaceTexture): Boolean

    fun setupEncoderSurface(surface: Surface): Boolean

    fun renderCameraToPreview(
        viewportWidth: Int,
        viewportHeight: Int,
        uvCoords: FloatArray? = null
    )

    fun renderCameraToEncoder(
        viewportWidth: Int,
        viewportHeight: Int,
        uvCoords: FloatArray?,
        presentationTimestampNs: Long
    ): Boolean

    /**
     * Renders the camera texture to an offscreen FBO, reads the pixels,
     * and compresses them as a JPEG image.
     *
     * @return JPEG bytes, or null on failure
     */
    fun renderCameraToJpeg(
        viewportWidth: Int,
        viewportHeight: Int,
        uvCoords: FloatArray?,
        jpegQuality: Int = 80
    ): ByteArray?

    fun makeCurrent()

    fun makeNothingCurrent()

    fun getDirectBufferUsageEstimateBytes(): Long

    fun hasPreviewSurface(): Boolean

    fun hasEncoderSurface(): Boolean

    fun release()
}
