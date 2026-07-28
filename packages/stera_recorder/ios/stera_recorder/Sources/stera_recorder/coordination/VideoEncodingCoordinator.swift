import Foundation
import AVFoundation

/// Coordinates video encoding setup, per-frame encoding, and finalization.
/// iOS version uses AVAssetWriter instead of MediaCodec.
/// Note: AVAssetWriter does not support dynamic bitrate changes after writing begins.
class VideoEncodingCoordinator {

    enum EncodeOutcome {
        case encoded
        case encoderFailure
    }

    struct SetupResult {
        let success: Bool
        let selectedBitrate: Int
        let targetVideoBitrate: Int
        let activeVideoBitrate: Int
        let actualVideoWidth: Int
        let actualVideoHeight: Int
        let encoderSurfaceReady: Bool
        let chosenFps: Int
        let chosenWidth: Int
        let chosenHeight: Int
    }

    struct EncodeResult {
        let outcome: EncodeOutcome
        let lastEncodedTimestampNs: Int64
        let actualVideoWidth: Int
        let actualVideoHeight: Int
    }

    struct EncoderFinalizeResult {
        let actualVideoWidth: Int
        let actualVideoHeight: Int
    }

    private let videoEncoder: VideoEncoder
    private let logSystem: (String) -> Void
    private let recordError: (String, Error?) -> Void
    private let onEncodedSampleSubmitted: () -> Void
    private var firstTimestampNs: Int64? = nil

    init(
        videoEncoder: VideoEncoder,
        logSystem: @escaping (String) -> Void,
        recordError: @escaping (String, Error?) -> Void,
        onEncodedSampleSubmitted: @escaping () -> Void
    ) {
        self.videoEncoder = videoEncoder
        self.logSystem = logSystem
        self.recordError = recordError
        self.onEncodedSampleSubmitted = onEncodedSampleSubmitted
    }

    func setupVideoEncoder(
        outputPath: String,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int
    ) -> SetupResult {
        guard let encoderResult = videoEncoder.setup(
            outputPath: outputPath,
            configuredVideoWidth: configuredVideoWidth,
            configuredVideoHeight: configuredVideoHeight,
            targetEncodeFps: targetEncodeFps,
            targetVideoBitrate: targetVideoBitrate
        ) else {
            return SetupResult(
                success: false,
                selectedBitrate: 0,
                targetVideoBitrate: targetVideoBitrate,
                activeVideoBitrate: 0,
                actualVideoWidth: 0,
                actualVideoHeight: 0,
                encoderSurfaceReady: false,
                chosenFps: targetEncodeFps,
                chosenWidth: configuredVideoWidth,
                chosenHeight: configuredVideoHeight
            )
        }

        return SetupResult(
            success: true,
            selectedBitrate: encoderResult.chosenBitrate,
            targetVideoBitrate: encoderResult.chosenBitrate,
            activeVideoBitrate: encoderResult.chosenBitrate,
            actualVideoWidth: encoderResult.chosenWidth,
            actualVideoHeight: encoderResult.chosenHeight,
            encoderSurfaceReady: true,
            chosenFps: encoderResult.chosenFps,
            chosenWidth: encoderResult.chosenWidth,
            chosenHeight: encoderResult.chosenHeight
        )
    }

    func encodeVideoFrame(
        pixelBuffer: CVPixelBuffer,
        timestampNs: Int64,
        lastEncodedTimestampNs: Int64
    ) -> EncodeResult {
        // Normalize timestamps to start from 0 so thumbnail extraction at time 0 works
        if firstTimestampNs == nil { firstTimestampNs = timestampNs }
        let normalizedNs = timestampNs - firstTimestampNs!
        let presentationTime = CMTime(value: CMTimeValue(normalizedNs), timescale: 1_000_000_000)

        let success = videoEncoder.encodeFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
        if success {
            onEncodedSampleSubmitted()
            return EncodeResult(
                outcome: .encoded,
                lastEncodedTimestampNs: timestampNs,
                actualVideoWidth: videoEncoder.actualVideoWidth,
                actualVideoHeight: videoEncoder.actualVideoHeight
            )
        } else {
            return EncodeResult(
                outcome: .encoderFailure,
                lastEncodedTimestampNs: lastEncodedTimestampNs,
                actualVideoWidth: videoEncoder.actualVideoWidth,
                actualVideoHeight: videoEncoder.actualVideoHeight
            )
        }
    }

    func finalizeVideoEncoder() -> EncoderFinalizeResult {
        videoEncoder.finalizeStream()
        return EncoderFinalizeResult(
            actualVideoWidth: videoEncoder.actualVideoWidth,
            actualVideoHeight: videoEncoder.actualVideoHeight
        )
    }

    func releaseVideoEncoder() {
        firstTimestampNs = nil
        videoEncoder.release()
    }
}
