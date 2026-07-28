import Foundation
import AVFoundation
import CoreImage
import ImageIO

/// AVAssetWriter-based H.264 video encoder.
/// Scales camera frames to target resolution using CIContext with Metal.
class VideoEncoderImpl: VideoEncoder {

    private let logSystem: (String) -> Void
    private let recordError: (String, Error?) -> Void
    private let onEncodedSample: () -> Void

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var ciContext: CIContext?
    private var isWriting: Bool = false

    private(set) var actualVideoWidth: Int = 0
    private(set) var actualVideoHeight: Int = 0
    private(set) var activeVideoBitrate: Int = 0

    private var targetWidth: Int = 720
    private var targetHeight: Int = 1280

    init(
        logSystem: @escaping (String) -> Void,
        recordError: @escaping (String, Error?) -> Void,
        onEncodedSample: @escaping () -> Void
    ) {
        self.logSystem = logSystem
        self.recordError = recordError
        self.onEncodedSample = onEncodedSample
    }

    func setup(
        outputPath: String,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int
    ) -> EncoderSetupResult? {
        release()

        targetWidth = configuredVideoWidth
        targetHeight = configuredVideoHeight

        let outputURL = URL(fileURLWithPath: outputPath)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: configuredVideoWidth,
                AVVideoHeightKey: configuredVideoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: targetVideoBitrate,
                    AVVideoMaxKeyFrameIntervalKey: targetEncodeFps,
                    AVVideoExpectedSourceFrameRateKey: targetEncodeFps,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                ]
            ]

            writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput?.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: configuredVideoWidth,
                kCVPixelBufferHeightKey as String: configuredVideoHeight
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            guard let writer = assetWriter, let input = writerInput else {
                return nil
            }

            if writer.canAdd(input) {
                writer.add(input)
            } else {
                recordError("Cannot add video input to asset writer", nil)
                return nil
            }

            if !writer.startWriting() {
                recordError("Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")", writer.error)
                return nil
            }

            writer.startSession(atSourceTime: .zero)

            // Create CIContext with Metal for efficient scaling
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                ciContext = CIContext(mtlDevice: metalDevice)
            } else {
                ciContext = CIContext()
            }

            actualVideoWidth = configuredVideoWidth
            actualVideoHeight = configuredVideoHeight
            activeVideoBitrate = targetVideoBitrate
            isWriting = true

            logSystem("Encoder configured: \(configuredVideoWidth)x\(configuredVideoHeight)@\(targetEncodeFps)fps bitrate=\(targetVideoBitrate)")

            return EncoderSetupResult(
                chosenBitrate: targetVideoBitrate,
                chosenFps: targetEncodeFps,
                chosenWidth: configuredVideoWidth,
                chosenHeight: configuredVideoHeight
            )
        } catch {
            recordError("Failed to setup AVAssetWriter", error)
            release()
            return nil
        }
    }

    func encodeFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        guard isWriting,
              let input = writerInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData else {
            return false
        }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)

        if srcWidth == targetWidth && srcHeight == targetHeight && srcHeight >= srcWidth {
            let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            if success { onEncodedSample() }
            return success
        }

        // Scale the pixel buffer using CIContext
        guard let context = ciContext,
              let pool = adaptor.pixelBufferPool else {
            return false
        }

        var scaledBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaledBuffer)
        guard status == kCVReturnSuccess, let outputBuffer = scaledBuffer else {
            return false
        }

        let portraitImage = normalizedPortraitImage(from: pixelBuffer)
        let orientedExtent = portraitImage.extent.integral
        let scaleX = CGFloat(targetWidth) / orientedExtent.width
        let scaleY = CGFloat(targetHeight) / orientedExtent.height
        let scale = max(scaleX, scaleY)
        let scaledImage = portraitImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledImage.extent.integral
        let centeredImage = scaledImage.transformed(
            by: CGAffineTransform(
                translationX: ((CGFloat(targetWidth) - scaledExtent.width) / 2.0) - scaledExtent.origin.x,
                y: ((CGFloat(targetHeight) - scaledExtent.height) / 2.0) - scaledExtent.origin.y
            )
        )
        let outputRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)

        context.render(centeredImage.cropped(to: outputRect), to: outputBuffer)

        let success = adaptor.append(outputBuffer, withPresentationTime: presentationTime)
        if success { onEncodedSample() }
        return success
    }

    func finalizeStream() {
        guard isWriting, let writer = assetWriter else { return }
        isWriting = false
        writerInput?.markAsFinished()

        print("VideoEncoder: finalizeStream - waiting for AVAssetWriter...")
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        let timeout = semaphore.wait(timeout: .now() + 5.0)
        if timeout == .timedOut {
            print("VideoEncoder: finalizeStream - AVAssetWriter timed out after 5s")
            recordError("AVAssetWriter finishWriting timed out after 5s", nil)
        } else if writer.status == .failed {
            print("VideoEncoder: finalizeStream - AVAssetWriter failed: \(writer.error?.localizedDescription ?? "unknown")")
            recordError("AVAssetWriter failed: \(writer.error?.localizedDescription ?? "unknown")", writer.error)
        } else {
            print("VideoEncoder: finalizeStream - AVAssetWriter finished, status: \(writer.status.rawValue)")
            logSystem("Video encoding finalized successfully")
        }
    }

    func release() {
        if isWriting {
            finalizeStream()
        }
        assetWriter = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        ciContext = nil
        isWriting = false
        actualVideoWidth = 0
        actualVideoHeight = 0
        activeVideoBitrate = 0
    }

    private func normalizedPortraitImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if height >= width {
            return ciImage
        }

        return ciImage.oriented(.right)
    }
}
