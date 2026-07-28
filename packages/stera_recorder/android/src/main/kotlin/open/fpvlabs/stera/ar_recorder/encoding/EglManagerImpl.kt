package open.fpvlabs.stera.ar_recorder.encoding

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLExt
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.view.Surface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Manages EGL context, OpenGL resources, and rendering for ARCore preview.
 */
class EglManagerImpl : EglManager {

    companion object {
        private const val GLES_VERSION = 2
        private val DEFAULT_UVS = floatArrayOf(0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f)
    }

    private var eglDisplay: EGLDisplay? = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext? = EGL14.EGL_NO_CONTEXT
    private var eglConfig: EGLConfig? = null
    private var pbufferSurface: EGLSurface? = EGL14.EGL_NO_SURFACE
    private var windowSurface: EGLSurface? = EGL14.EGL_NO_SURFACE
    private var encoderSurface: EGLSurface? = EGL14.EGL_NO_SURFACE

    override var cameraTextureId: Int = 0
        private set

    private var previewSurface: Surface? = null
    private var encoderInputSurface: Surface? = null

    // Shader program
    private var program: Int = 0
    private var positionAttrib: Int = 0
    private var texCoordAttrib: Int = 0
    private var textureUniform: Int = 0

    private val previewVertices = FloatArray(16)
    private val encoderVertices = FloatArray(16)
    private val captureVertices = FloatArray(16)
    private val previewVertexBuffer = java.nio.ByteBuffer.allocateDirect(16 * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()
    private val encoderVertexBuffer = java.nio.ByteBuffer.allocateDirect(16 * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()
    private val captureVertexBuffer = java.nio.ByteBuffer.allocateDirect(16 * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()

    // Offscreen FBO for JPEG capture
    private var captureFbo: Int = 0
    private var captureTexId: Int = 0
    private var captureWidth: Int = 0
    private var captureHeight: Int = 0
    private var capturePixelBuffer: ByteBuffer? = null
    private var captureBitmap: Bitmap? = null

    /**
     * Initializes EGL display, context, and creates camera texture.
     */
    override fun initialize(): Boolean {
        try {
            // Create EGL display
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
                throw RuntimeException("Unable to get EGL display")
            }

            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
                throw RuntimeException("Unable to initialize EGL")
            }

            // Choose EGL config
            val configAttribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_DEPTH_SIZE, 16,
                EGL14.EGL_STENCIL_SIZE, 8,
                EGL14.EGL_NONE
            )

            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)) {
                throw RuntimeException("Unable to choose EGL config")
            }

            eglConfig = configs[0]

            // Create EGL context
            val contextAttribs = intArrayOf(
                EGL14.EGL_CONTEXT_CLIENT_VERSION, GLES_VERSION,
                EGL14.EGL_NONE
            )

            eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
            if (eglContext == EGL14.EGL_NO_CONTEXT) {
                throw RuntimeException("Unable to create EGL context")
            }

            // Create PBuffer surface (required for off-screen rendering)
            val surfaceAttribs = intArrayOf(
                EGL14.EGL_WIDTH, 1,
                EGL14.EGL_HEIGHT, 1,
                EGL14.EGL_NONE
            )
            pbufferSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, surfaceAttribs, 0)

            // Make context current with PBuffer surface initially
            makeCurrent()

            // Create camera texture (OES)
            createCameraTexture()

            // Create shader program
            createShaderProgram()

            println("✅ EGL initialized successfully")
            return true

        } catch (e: Exception) {
            println("❌ Failed to initialize EGL: ${e.message}")
            e.printStackTrace()
            release()
            return false
        }
    }

    /**
     * Creates the camera texture for ARCore.
     */
    private fun createCameraTexture() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTextureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        println("✅ Camera texture created: $cameraTextureId")
    }

    /**
     * Creates the shader program for OES texture rendering.
     */
    private fun createShaderProgram() {
        val vertexShaderCode = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """.trimIndent()

        val fragmentShaderCode = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
                gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """.trimIndent()

        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexShaderCode)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderCode)

        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            val error = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw RuntimeException("Failed to link shader program: $error")
        }

        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttrib = GLES20.glGetAttribLocation(program, "a_TexCoord")
        textureUniform = GLES20.glGetUniformLocation(program, "u_Texture")

        println("✅ Shader program created")
    }

    /**
     * Compiles a shader.
     */
    private fun loadShader(type: Int, code: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, code)
        GLES20.glCompileShader(shader)

        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            val error = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("Failed to compile shader: $error")
        }
        return shader
    }

    /**
     * Sets up the preview surface from Flutter's SurfaceTexture.
     */
    override fun setupPreviewSurface(surfaceTexture: SurfaceTexture): Boolean {
        try {
            previewSurface = Surface(surfaceTexture)

            // Create window surface for preview
            windowSurface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, previewSurface, intArrayOf(EGL14.EGL_NONE), 0)
            if (windowSurface == EGL14.EGL_NO_SURFACE) {
                throw RuntimeException("Unable to create window surface")
            }

            println("✅ Preview surface set up")
            return true
        } catch (e: Exception) {
            println("❌ Failed to set up preview surface: ${e.message}")
            e.printStackTrace()
            return false
        }
    }

    override fun setupEncoderSurface(surface: Surface): Boolean {
        return try {
            if (encoderSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, encoderSurface)
                encoderSurface = EGL14.EGL_NO_SURFACE
            }
            encoderInputSurface?.release()
            encoderInputSurface = surface
            encoderSurface = EGL14.eglCreateWindowSurface(
                eglDisplay,
                eglConfig,
                encoderInputSurface,
                intArrayOf(EGL14.EGL_NONE),
                0
            )
            if (encoderSurface == EGL14.EGL_NO_SURFACE) {
                throw RuntimeException("Unable to create encoder EGL surface")
            }
            println("✅ Encoder surface set up")
            true
        } catch (e: Exception) {
            println("❌ Failed to set up encoder surface: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    /**
     * Renders the camera texture to the preview surface.
     * @param viewportWidth Width of the preview viewport
     * @param viewportHeight Height of the preview viewport  
     * @param uvCoords Optional transformed UV coordinates from ARCore (8 floats: u0,v0,u1,v1,u2,v2,u3,v3)
     *                   If null, uses default identity UVs
     */
    override fun renderCameraToPreview(viewportWidth: Int, viewportHeight: Int, uvCoords: FloatArray?) {
        if (windowSurface == EGL14.EGL_NO_SURFACE) return

        // Make window surface current
        EGL14.eglMakeCurrent(eglDisplay, windowSurface, windowSurface, eglContext)

        // Set viewport
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        // Use shader program
        GLES20.glUseProgram(program)

        // Set up geometry (fullscreen quad with transformed UVs)
        // Layout: position_x, position_y, texcoord_u, texcoord_v
        // Use transformed UVs if provided, otherwise use identity
        val uvs = uvCoords ?: DEFAULT_UVS

        // FIX: Swapped Y coordinates to correct vertical flip
        // OpenGL NDC: (-1,-1) is bottom-left, (-1,1) is top-left
        // We map screen positions to match UV output from ARCore
        previewVertices[0] = -1.0f
        previewVertices[1] = 1.0f
        previewVertices[2] = uvs[0]
        previewVertices[3] = uvs[1]
        previewVertices[4] = 1.0f
        previewVertices[5] = 1.0f
        previewVertices[6] = uvs[2]
        previewVertices[7] = uvs[3]
        previewVertices[8] = -1.0f
        previewVertices[9] = -1.0f
        previewVertices[10] = uvs[4]
        previewVertices[11] = uvs[5]
        previewVertices[12] = 1.0f
        previewVertices[13] = -1.0f
        previewVertices[14] = uvs[6]
        previewVertices[15] = uvs[7]

        val vertexBuffer = previewVertexBuffer
        vertexBuffer.clear()
        vertexBuffer.put(previewVertices)
        vertexBuffer.position(0)

        // Set up attributes
        GLES20.glVertexAttribPointer(positionAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(positionAttrib)

        vertexBuffer.position(2)
        GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(texCoordAttrib)

        // Bind camera texture
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(textureUniform, 0)

        // Draw
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        // Swap buffers - this makes the frame available to Flutter's SurfaceTexture
        EGL14.eglSwapBuffers(eglDisplay, windowSurface)
    }

    override fun renderCameraToEncoder(
        viewportWidth: Int,
        viewportHeight: Int,
        uvCoords: FloatArray?,
        presentationTimestampNs: Long
    ): Boolean {
        if (encoderSurface == EGL14.EGL_NO_SURFACE) return false

        EGL14.eglMakeCurrent(eglDisplay, encoderSurface, encoderSurface, eglContext)
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        val uvs = uvCoords ?: DEFAULT_UVS
        encoderVertices[0] = -1.0f
        encoderVertices[1] = 1.0f
        encoderVertices[2] = uvs[0]
        encoderVertices[3] = uvs[1]
        encoderVertices[4] = 1.0f
        encoderVertices[5] = 1.0f
        encoderVertices[6] = uvs[2]
        encoderVertices[7] = uvs[3]
        encoderVertices[8] = -1.0f
        encoderVertices[9] = -1.0f
        encoderVertices[10] = uvs[4]
        encoderVertices[11] = uvs[5]
        encoderVertices[12] = 1.0f
        encoderVertices[13] = -1.0f
        encoderVertices[14] = uvs[6]
        encoderVertices[15] = uvs[7]
        val vertexBuffer = encoderVertexBuffer
        vertexBuffer.clear()
        vertexBuffer.put(encoderVertices)
        vertexBuffer.position(0)

        GLES20.glVertexAttribPointer(positionAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        vertexBuffer.position(2)
        GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
        GLES20.glEnableVertexAttribArray(texCoordAttrib)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(textureUniform, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        EGLExt.eglPresentationTimeANDROID(eglDisplay, encoderSurface, presentationTimestampNs)
        return EGL14.eglSwapBuffers(eglDisplay, encoderSurface)
    }

    private fun ensureCaptureFbo(width: Int, height: Int) {
        if (captureWidth == width && captureHeight == height && captureFbo != 0) return

        // Clean up old resources
        if (captureFbo != 0) {
            GLES20.glDeleteFramebuffers(1, intArrayOf(captureFbo), 0)
            GLES20.glDeleteTextures(1, intArrayOf(captureTexId), 0)
        }
        captureBitmap?.recycle()

        // Create texture for color attachment (RGBA8)
        val texIds = IntArray(1)
        GLES20.glGenTextures(1, texIds, 0)
        captureTexId = texIds[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, captureTexId)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA,
            width, height, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null
        )
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        // Create FBO
        val fboIds = IntArray(1)
        GLES20.glGenFramebuffers(1, fboIds, 0)
        captureFbo = fboIds[0]
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, captureFbo)
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, captureTexId, 0
        )

        val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
        if (status != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            println("❌ Capture FBO not complete: $status")
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)

        captureWidth = width
        captureHeight = height
        capturePixelBuffer = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
        captureBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

        println("✅ Capture FBO created: ${width}x${height}")
    }

    override fun renderCameraToJpeg(
        viewportWidth: Int,
        viewportHeight: Int,
        uvCoords: FloatArray?,
        jpegQuality: Int
    ): ByteArray? {
        return try {
            // Make pbuffer current for offscreen rendering
            EGL14.eglMakeCurrent(eglDisplay, pbufferSurface, pbufferSurface, eglContext)

            ensureCaptureFbo(viewportWidth, viewportHeight)

            // Bind FBO and render
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, captureFbo)
            GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(program)

            val uvs = uvCoords ?: DEFAULT_UVS

            // Flip Y so glReadPixels (bottom-up) produces a top-down image
            captureVertices[0] = -1.0f; captureVertices[1] = -1.0f  // bottom-left → top-left UV
            captureVertices[2] = uvs[0]; captureVertices[3] = uvs[1]
            captureVertices[4] = 1.0f; captureVertices[5] = -1.0f   // bottom-right → top-right UV
            captureVertices[6] = uvs[2]; captureVertices[7] = uvs[3]
            captureVertices[8] = -1.0f; captureVertices[9] = 1.0f   // top-left → bottom-left UV
            captureVertices[10] = uvs[4]; captureVertices[11] = uvs[5]
            captureVertices[12] = 1.0f; captureVertices[13] = 1.0f  // top-right → bottom-right UV
            captureVertices[14] = uvs[6]; captureVertices[15] = uvs[7]

            val vertexBuffer = captureVertexBuffer
            vertexBuffer.clear()
            vertexBuffer.put(captureVertices)
            vertexBuffer.position(0)

            GLES20.glVertexAttribPointer(positionAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            GLES20.glEnableVertexAttribArray(positionAttrib)
            vertexBuffer.position(2)
            GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            GLES20.glEnableVertexAttribArray(texCoordAttrib)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
            GLES20.glUniform1i(textureUniform, 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

            // Read pixels
            val pixelBuf = capturePixelBuffer ?: return null
            pixelBuf.rewind()
            GLES20.glReadPixels(0, 0, viewportWidth, viewportHeight, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixelBuf)

            // Unbind FBO
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)

            // Copy pixels to bitmap and compress to JPEG
            val bitmap = captureBitmap ?: return null
            pixelBuf.rewind()
            bitmap.copyPixelsFromBuffer(pixelBuf)

            val baos = ByteArrayOutputStream(viewportWidth * viewportHeight / 10) // rough estimate
            bitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, baos)
            baos.toByteArray()
        } catch (e: Exception) {
            println("❌ Failed to capture JPEG frame: ${e.message}")
            null
        }
    }

    /**
     * Makes the EGL context current with the PBuffer surface.
     */
    override fun makeCurrent() {
        EGL14.eglMakeCurrent(eglDisplay, pbufferSurface, pbufferSurface, eglContext)
    }

    /**
     * Makes no context current on this thread.
     * Required to transfer context ownership to another thread.
     */
    override fun makeNothingCurrent() {
        EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
    }

    override fun getDirectBufferUsageEstimateBytes(): Long {
        return (16L * 4L) + (16L * 4L)
    }

    override fun hasPreviewSurface(): Boolean {
        return windowSurface != EGL14.EGL_NO_SURFACE
    }

    override fun hasEncoderSurface(): Boolean {
        return encoderSurface != EGL14.EGL_NO_SURFACE
    }

    /**
     * Releases all EGL resources.
     */
    override fun release() {
        try {
            // Make context current before deleting GL resources
            if (eglDisplay != EGL14.EGL_NO_DISPLAY && eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglMakeCurrent(eglDisplay, pbufferSurface, pbufferSurface, eglContext)
            }

            // Clean up capture FBO
            if (captureFbo != 0) {
                GLES20.glDeleteFramebuffers(1, intArrayOf(captureFbo), 0)
                captureFbo = 0
            }
            if (captureTexId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(captureTexId), 0)
                captureTexId = 0
            }
            captureBitmap?.recycle()
            captureBitmap = null
            capturePixelBuffer = null
            captureWidth = 0
            captureHeight = 0

            if (program != 0) {
                GLES20.glDeleteProgram(program)
                program = 0
            }

            if (cameraTextureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(cameraTextureId), 0)
                cameraTextureId = 0
            }

            if (windowSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, windowSurface)
                windowSurface = EGL14.EGL_NO_SURFACE
            }

            if (encoderSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, encoderSurface)
                encoderSurface = EGL14.EGL_NO_SURFACE
            }

            if (pbufferSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, pbufferSurface)
                pbufferSurface = EGL14.EGL_NO_SURFACE
            }

            // Unbind context before destroying
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            }

            if (eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                eglContext = EGL14.EGL_NO_CONTEXT
            }

            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglTerminate(eglDisplay)
                eglDisplay = EGL14.EGL_NO_DISPLAY
            }

            previewSurface?.release()
            previewSurface = null
            encoderInputSurface?.release()
            encoderInputSurface = null

            println("✅ EGL resources released")
        } catch (e: Exception) {
            println("❌ Failed to release EGL: ${e.message}")
            e.printStackTrace()
        }
    }
}
