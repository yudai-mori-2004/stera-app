package open.fpvlabs.stera.ar_recorder.coordination

import open.fpvlabs.stera.ar_recorder.encoding.EglManager
import open.fpvlabs.stera.ar_recorder.encoding.EncoderSetupResult
import open.fpvlabs.stera.ar_recorder.encoding.VideoEncoder
import com.google.ar.core.Frame
import java.io.File

class VideoEncodingCoordinator(
    private val videoEncoder: VideoEncoder,
    private val eglManager: EglManager,
    private val logSystem: (String) -> Unit,
    private val recordError: (String, Throwable?) -> Unit,
    private val onEncodedSampleSubmitted: () -> Unit
) {
    enum class EncodeOutcome {
        ENCODED,
        ENCODER_FAILURE
    }

    data class SetupResult(
        val success: Boolean,
        val selectedBitrate: Int,
        val targetVideoBitrate: Int,
        val activeVideoBitrate: Int,
        val actualVideoWidth: Int,
        val actualVideoHeight: Int,
        val encoderSurfaceReady: Boolean,
        val chosenFps: Int,
        val chosenWidth: Int,
        val chosenHeight: Int
    )

    data class EncodeResult(
        val outcome: EncodeOutcome,
        val lastEncodedTimestampNs: Long,
        val actualVideoWidth: Int,
        val actualVideoHeight: Int
    )

    data class EncoderFinalizeResult(
        val actualVideoWidth: Int,
        val actualVideoHeight: Int
    )

    data class BitrateAdjustResult(
        val activeVideoBitrate: Int,
        val bitrateStableSinceMs: Long,
        val bitrateReducedCount: Int,
        val bitrateRestoreCount: Int
    )

    fun setupVideoEncoder(
        outputFile: File,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int,
        fallbackBitrate: Int,
        iFrameIntervalSeconds: Int
    ): SetupResult {
        val encoderResult = videoEncoder.setup(
            outputFile = outputFile,
            configuredVideoWidth = configuredVideoWidth,
            configuredVideoHeight = configuredVideoHeight,
            targetEncodeFps = targetEncodeFps,
            targetVideoBitrate = targetVideoBitrate,
            fallbackBitrate = fallbackBitrate,
            iFrameIntervalSeconds = iFrameIntervalSeconds
        ) ?: return SetupResult(
            success = false,
            selectedBitrate = 0,
            targetVideoBitrate = targetVideoBitrate,
            activeVideoBitrate = 0,
            actualVideoWidth = 0,
            actualVideoHeight = 0,
            encoderSurfaceReady = false,
            chosenFps = targetEncodeFps,
            chosenWidth = configuredVideoWidth,
            chosenHeight = configuredVideoHeight
        )
        var updatedTargetBitrate = targetVideoBitrate
        if (encoderResult.chosenBitrate != targetVideoBitrate) {
            updatedTargetBitrate = encoderResult.chosenBitrate
            logSystem(
                "FALLBACK: using bitrate=${encoderResult.chosenBitrate} because requested bitrate could not be configured"
            )
        }
        if (encoderResult.chosenFps != targetEncodeFps || encoderResult.chosenWidth != configuredVideoWidth || encoderResult.chosenHeight != configuredVideoHeight) {
            logSystem(
                "FALLBACK: encoder fell back to ${encoderResult.chosenWidth}x${encoderResult.chosenHeight}@${encoderResult.chosenFps}fps (requested ${configuredVideoWidth}x${configuredVideoHeight}@${targetEncodeFps}fps)"
            )
        }
        return SetupResult(
            success = true,
            selectedBitrate = encoderResult.chosenBitrate,
            targetVideoBitrate = updatedTargetBitrate,
            activeVideoBitrate = encoderResult.chosenBitrate,
            actualVideoWidth = 0,
            actualVideoHeight = 0,
            encoderSurfaceReady = false,
            chosenFps = encoderResult.chosenFps,
            chosenWidth = encoderResult.chosenWidth,
            chosenHeight = encoderResult.chosenHeight
        )
    }

    private fun ensureEncoderSurfaceReady(): Boolean {
        return videoEncoder.ensureEncoderSurfaceReady(eglManager)
    }

    fun encodeVideoFrame(
        timestampNs: Long,
        frame: Frame,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        lastEncodedTimestampNs: Long,
        transformedUvs: FloatArray
    ): EncodeResult {
        if (!ensureEncoderSurfaceReady()) {
            return EncodeResult(EncodeOutcome.ENCODER_FAILURE, lastEncodedTimestampNs, videoEncoder.actualVideoWidth, videoEncoder.actualVideoHeight)
        }

        val rendered = try {
            eglManager.renderCameraToEncoder(
                viewportWidth = configuredVideoWidth,
                viewportHeight = configuredVideoHeight,
                uvCoords = transformedUvs,
                presentationTimestampNs = timestampNs
            )
        } catch (e: Exception) {
            recordError("Failed to render frame to encoder", e)
            false
        }
        if (!rendered) {
            return EncodeResult(EncodeOutcome.ENCODER_FAILURE, lastEncodedTimestampNs, videoEncoder.actualVideoWidth, videoEncoder.actualVideoHeight)
        }

        onEncodedSampleSubmitted()
        return try {
            videoEncoder.drain(
                endOfStream = false,
                configuredVideoWidth = configuredVideoWidth,
                configuredVideoHeight = configuredVideoHeight,
                targetEncodeFps = targetEncodeFps
            )
            EncodeResult(
                outcome = EncodeOutcome.ENCODED,
                lastEncodedTimestampNs = timestampNs,
                actualVideoWidth = videoEncoder.actualVideoWidth,
                actualVideoHeight = videoEncoder.actualVideoHeight
            )
        } catch (e: Exception) {
            recordError("Failed to drain encoder", e)
            EncodeResult(EncodeOutcome.ENCODER_FAILURE, lastEncodedTimestampNs, videoEncoder.actualVideoWidth, videoEncoder.actualVideoHeight)
        }
    }

    fun finalizeVideoEncoder(
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    ): EncoderFinalizeResult {
        videoEncoder.finalizeStream(
            configuredVideoWidth = configuredVideoWidth,
            configuredVideoHeight = configuredVideoHeight,
            targetEncodeFps = targetEncodeFps
        )
        return EncoderFinalizeResult(
            actualVideoWidth = videoEncoder.actualVideoWidth,
            actualVideoHeight = videoEncoder.actualVideoHeight
        )
    }

    fun drainVideoEncoder(
        endOfStream: Boolean,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int
    ): EncoderFinalizeResult {
        videoEncoder.drain(
            endOfStream = endOfStream,
            configuredVideoWidth = configuredVideoWidth,
            configuredVideoHeight = configuredVideoHeight,
            targetEncodeFps = targetEncodeFps
        )
        return EncoderFinalizeResult(
            actualVideoWidth = videoEncoder.actualVideoWidth,
            actualVideoHeight = videoEncoder.actualVideoHeight
        )
    }

    fun releaseVideoEncoder() {
        videoEncoder.release()
    }

    fun applyEncoderBitrate(newBitrate: Int): Int? {
        val applied = videoEncoder.applyBitrate(newBitrate)
        return if (applied) videoEncoder.activeVideoBitrate else null
    }

    fun maybeAdjustEncoderBitrate(
        nowMs: Long,
        queueDepth: Int,
        thermalBitrateClampActive: Boolean,
        activeVideoBitrate: Int,
        targetVideoBitrate: Int,
        bitrateStableSinceMs: Long,
        bitrateReducedCount: Int,
        bitrateRestoreCount: Int,
        videoBitrateFallback: Int,
        encoderQueueSoftLimit: Int,
        bitrateReductionTriggerQueueDepth: Int,
        bitrateRestoreStableWindowMs: Long,
        bitrateAdjustmentStepPercent: Int
    ): BitrateAdjustResult {
        var updatedActiveBitrate = activeVideoBitrate
        var updatedStableSinceMs = bitrateStableSinceMs
        var updatedReducedCount = bitrateReducedCount
        var updatedRestoreCount = bitrateRestoreCount

        if (thermalBitrateClampActive) {
            updatedStableSinceMs = 0L
            if (updatedActiveBitrate > videoBitrateFallback) {
                applyEncoderBitrate(videoBitrateFallback)?.let { updatedActiveBitrate = it }
            }
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        if (queueDepth > bitrateReductionTriggerQueueDepth) {
            updatedStableSinceMs = 0L
            val reducedBitrate =
                (updatedActiveBitrate * (100 - bitrateAdjustmentStepPercent) / 100).coerceAtLeast(videoBitrateFallback)
            if (reducedBitrate < updatedActiveBitrate) {
                applyEncoderBitrate(reducedBitrate)?.let {
                    updatedActiveBitrate = it
                    updatedReducedCount++
                    logSystem("Dynamic bitrate reduce: queue_depth=$queueDepth bitrate=$updatedActiveBitrate")
                }
            }
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        if (queueDepth > encoderQueueSoftLimit) {
            updatedStableSinceMs = 0L
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        if (updatedStableSinceMs == 0L) {
            updatedStableSinceMs = nowMs
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        if (nowMs - updatedStableSinceMs < bitrateRestoreStableWindowMs) {
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        if (updatedActiveBitrate >= targetVideoBitrate) {
            updatedStableSinceMs = nowMs
            return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
        }

        val restoredBitrate =
            (updatedActiveBitrate * (100 + bitrateAdjustmentStepPercent) / 100).coerceAtMost(targetVideoBitrate)
        if (restoredBitrate > updatedActiveBitrate) {
            applyEncoderBitrate(restoredBitrate)?.let {
                updatedActiveBitrate = it
                updatedRestoreCount++
                updatedStableSinceMs = nowMs
                logSystem("Dynamic bitrate restore: queue_depth=$queueDepth bitrate=$updatedActiveBitrate")
            }
        }

        return BitrateAdjustResult(updatedActiveBitrate, updatedStableSinceMs, updatedReducedCount, updatedRestoreCount)
    }
}
