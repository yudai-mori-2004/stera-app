import Foundation
import AVFoundation
import CoreVideo

struct EncoderSetupResult {
    let chosenBitrate: Int
    let chosenFps: Int
    let chosenWidth: Int
    let chosenHeight: Int
}

protocol VideoEncoder {
    var actualVideoWidth: Int { get }
    var actualVideoHeight: Int { get }
    var activeVideoBitrate: Int { get }

    func setup(
        outputPath: String,
        configuredVideoWidth: Int,
        configuredVideoHeight: Int,
        targetEncodeFps: Int,
        targetVideoBitrate: Int
    ) -> EncoderSetupResult?

    func encodeFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool
    func finalizeStream()
    func release()
}
