package open.fpvlabs.stera.ar_recorder.encoding

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Bundle
import android.view.Surface
import java.io.File

/**
 * Encapsulates MediaCodec/MediaMuxer lifecycle and bitrate changes.
 */
class VideoEncoderImpl(
    private val logSystem: (String) -> Unit,
    private val recordError: (String, Throwable?) -> Unit,
    private val onEncodedSample: () -> Unit
) : VideoEncoder {
    private var videoCodec: MediaCodec? = null
    private var videoMuxer: android.media.MediaMuxer? = null
    private var encoderInputSurface: Surface? = null
    private var muxerTrackIndex: Int = -1
    private var muxerStarted: Boolean = false
    private var encoderSurfaceReady: Boolean = false

    // Reused across drain() calls (drain is single-threaded — MediaCodec/MediaMuxer
    // aren't thread-safe) so we don't allocate a BufferInfo per drained frame.
    private val drainBufferInfo = MediaCodec.BufferInfo()

    override var actualVideoWidth: Int = 0
        private set
    override var actualVideoHeight: Int = 0
        private set
    override var activeVideoBitrate: Int = 0
        private set

    private data class EncoderCandidate(
        val width: Int,
        val height: Int,
        val fps: Int,
        val bitrate: Int,
        val useExplicitProfile: Boolean
    )

    override fun setup(
        outputFile: File,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int,
        fallbackBitrate: Int,
        iFrameIntervalSeconds: Int
    ): EncoderSetupResult? {
        // Reduced resolution aligned to 16px
        val reducedWidth = (configuredVideoWidth * 3 / 4) / 16 * 16
        val reducedHeight = (configuredVideoHeight * 3 / 4) / 16 * 16
        val reducedFps = (targetEncodeFps * 4 / 5).coerceAtLeast(20)

        val candidates = listOf(
            // Full resolution, full fps, no explicit profile (most likely fix for devices that reject AVCProfileBaseline)
            EncoderCandidate(configuredVideoWidth, configuredVideoHeight, targetEncodeFps, targetVideoBitrate, useExplicitProfile = false),
            EncoderCandidate(configuredVideoWidth, configuredVideoHeight, targetEncodeFps, fallbackBitrate, useExplicitProfile = false),
            // Full resolution, full fps, explicit baseline profile (original behavior)
            EncoderCandidate(configuredVideoWidth, configuredVideoHeight, targetEncodeFps, fallbackBitrate, useExplicitProfile = true),
            // Full resolution, reduced fps
            EncoderCandidate(configuredVideoWidth, configuredVideoHeight, reducedFps, (fallbackBitrate * 3 / 4).coerceAtLeast(4_000_000), useExplicitProfile = false),
            EncoderCandidate(configuredVideoWidth, configuredVideoHeight, reducedFps, (fallbackBitrate / 2).coerceAtLeast(3_000_000), useExplicitProfile = false),
            // Reduced resolution, reduced fps
            EncoderCandidate(reducedWidth, reducedHeight, reducedFps, (fallbackBitrate / 2).coerceAtLeast(3_000_000), useExplicitProfile = false),
            EncoderCandidate(reducedWidth, reducedHeight, reducedFps, (fallbackBitrate * 3 / 8).coerceAtLeast(2_000_000), useExplicitProfile = false)
        )

        for ((index, candidate) in candidates.withIndex()) {
            try {
                release()

                val format = MediaFormat.createVideoFormat("video/avc", candidate.width, candidate.height).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                    setInteger(MediaFormat.KEY_BIT_RATE, candidate.bitrate)
                    setInteger(MediaFormat.KEY_FRAME_RATE, candidate.fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, iFrameIntervalSeconds)
                    if (candidate.useExplicitProfile) {
                        setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                    }
                }

                videoCodec = MediaCodec.createEncoderByType("video/avc")
                videoCodec?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoderInputSurface = videoCodec?.createInputSurface()
                videoCodec?.start()

                videoMuxer = android.media.MediaMuxer(
                    outputFile.absolutePath,
                    android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
                )

                activeVideoBitrate = candidate.bitrate
                actualVideoWidth = 0
                actualVideoHeight = 0
                muxerTrackIndex = -1
                muxerStarted = false
                encoderSurfaceReady = false

                logSystem(
                    "Encoder configured: candidate=$index ${candidate.width}x${candidate.height}@${candidate.fps}fps bitrate=${candidate.bitrate} profile=${if (candidate.useExplicitProfile) "AVCProfileBaseline" else "default"}"
                )

                return EncoderSetupResult(
                    chosenBitrate = candidate.bitrate,
                    chosenFps = candidate.fps,
                    chosenWidth = candidate.width,
                    chosenHeight = candidate.height
                )
            } catch (e: Exception) {
                recordError("Failed to setup video encoder candidate=$index ${candidate.width}x${candidate.height}@${candidate.fps}fps bitrate=${candidate.bitrate}", e)
                logSystem(
                    "FALLBACK: could not configure candidate=$index ${candidate.width}x${candidate.height}@${candidate.fps}fps AVC encoder bitrate=${candidate.bitrate} profile=${if (candidate.useExplicitProfile) "baseline" else "default"}: ${e.message}"
                )
                release()
            }
        }
        return null
    }

    override fun ensureEncoderSurfaceReady(eglManager: EglManager): Boolean {
        if (encoderSurfaceReady) return true
        val surface = encoderInputSurface ?: return false
        encoderSurfaceReady = eglManager.setupEncoderSurface(surface)
        return encoderSurfaceReady
    }

    override fun applyBitrate(newBitrate: Int): Boolean {
        val codec = videoCodec ?: return false
        return try {
            val params = Bundle()
            params.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, newBitrate)
            codec.setParameters(params)
            activeVideoBitrate = newBitrate
            true
        } catch (e: Exception) {
            recordError("Failed to update encoder bitrate to $newBitrate", e)
            false
        }
    }

    override fun drain(
        endOfStream: Boolean,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    ) {
        val codec = videoCodec ?: return
        val muxer = videoMuxer ?: return
        val bufferInfo = drainBufferInfo

        while (true) {
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            when {
                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (muxerStarted) {
                        throw IllegalStateException("Output format changed twice")
                    }
                    val newFormat = codec.outputFormat
                    actualVideoWidth = if (newFormat.containsKey(MediaFormat.KEY_WIDTH)) {
                        newFormat.getInteger(MediaFormat.KEY_WIDTH)
                    } else {
                        configuredVideoWidth
                    }
                    actualVideoHeight = if (newFormat.containsKey(MediaFormat.KEY_HEIGHT)) {
                        newFormat.getInteger(MediaFormat.KEY_HEIGHT)
                    } else {
                        configuredVideoHeight
                    }
                    logSystem(
                        "Video format: configured_width=$configuredVideoWidth configured_height=$configuredVideoHeight actual_width=$actualVideoWidth actual_height=$actualVideoHeight fps_target=$targetEncodeFps"
                    )
                    if (actualVideoWidth != configuredVideoWidth || actualVideoHeight != configuredVideoHeight) {
                        logSystem(
                            "resolution_adjusted=true actual=${actualVideoWidth}x${actualVideoHeight} expected=${configuredVideoWidth}x${configuredVideoHeight} — accepting encoder output"
                        )
                    }
                    muxerTrackIndex = muxer.addTrack(newFormat)
                    muxer.start()
                    muxerStarted = true
                }

                outputIndex >= 0 -> {
                    val outputBuffer = codec.getOutputBuffer(outputIndex)
                    if (outputBuffer != null && bufferInfo.size > 0 && muxerStarted) {
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(muxerTrackIndex, outputBuffer, bufferInfo)
                        onEncodedSample()
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        return
                    }
                }
            }
        }
    }

    override fun finalizeStream(
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    ) {
        try {
            videoCodec?.signalEndOfInputStream()
            drain(
                endOfStream = true,
                configuredVideoWidth = configuredVideoWidth,
                configuredVideoHeight = configuredVideoHeight,
                targetEncodeFps = targetEncodeFps
            )
        } catch (e: Exception) {
            recordError("Failed to finalize encoder stream", e)
        } finally {
            release()
        }
    }

    override fun release() {
        try {
            videoCodec?.stop()
        } catch (_: Exception) {
        }
        try {
            videoCodec?.release()
        } catch (_: Exception) {
        }
        try {
            if (muxerStarted) {
                videoMuxer?.stop()
            }
        } catch (_: Exception) {
        }
        try {
            videoMuxer?.release()
        } catch (_: Exception) {
        }
        try {
            encoderInputSurface?.release()
        } catch (_: Exception) {
        }
        videoCodec = null
        videoMuxer = null
        encoderInputSurface = null
        muxerTrackIndex = -1
        muxerStarted = false
        encoderSurfaceReady = false
    }
}
