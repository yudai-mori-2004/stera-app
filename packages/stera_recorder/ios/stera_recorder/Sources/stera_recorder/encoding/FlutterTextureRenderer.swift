import Foundation
import CoreImage
import CoreVideo
import Flutter
import UIKit

/// Provides ARKit camera frames as a Flutter texture.
/// Conforms to FlutterTexture to supply CVPixelBuffer to the Flutter texture registry.
/// Much simpler than the Android EGL pipeline.
class FlutterTextureRenderer: NSObject, FlutterTexture {

    private var previewWidth: Int = 1280
    private var previewHeight: Int = 720

    private var textureRegistry: FlutterTextureRegistry?
    private(set) var textureId: Int64 = -1
    private var latestPixelBuffer: CVPixelBuffer?
    private var lock = os_unfair_lock()
    private let ciContext = CIContext()
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    func register(with registry: FlutterTextureRegistry) {
        textureRegistry = registry
        textureId = registry.register(self)
        print("Flutter texture registered: \(textureId)")
    }

    func configurePreviewSize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if previewWidth == width && previewHeight == height { return }
        previewWidth = width
        previewHeight = height
        os_unfair_lock_lock(&lock)
        latestPixelBuffer = nil
        os_unfair_lock_unlock(&lock)
        pixelBufferPool = nil
        poolWidth = 0
        poolHeight = 0
    }

    var currentPreviewWidth: Int { previewWidth }
    var currentPreviewHeight: Int { previewHeight }

    /// Drops the last rendered frame so a stale image isn't shown when the
    /// preview source changes. Without
    /// this the previous camera's last frame lingers in the texture until the
    /// new source delivers its first frame, briefly flashing the wrong feed.
    func clearLatestFrame() {
        os_unfair_lock_lock(&lock)
        latestPixelBuffer = nil
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textureRegistry?.textureFrameAvailable(self.textureId)
        }
    }

    /// Renders a preview frame from pre-extracted data.
    /// `capturedImage` and `displayTransform` must be extracted from the ARFrame
    /// on the delegate thread BEFORE dispatching to the texture queue.
    func updateFrame(capturedImage: CVPixelBuffer, displayTransform: CGAffineTransform) {
        guard let outputBuffer = makePreviewBuffer(
            width: previewWidth,
            height: previewHeight
        ) else {
            return
        }

        let viewportSize = CGSize(width: CGFloat(previewWidth), height: CGFloat(previewHeight))
        let renderedImage = makeRenderedPreviewImage(
            capturedImage: capturedImage,
            displayTransform: displayTransform,
            viewportSize: viewportSize
        )
        let outputRect = CGRect(origin: .zero, size: viewportSize)

        ciContext.render(renderedImage.cropped(to: outputRect), to: outputBuffer)

        os_unfair_lock_lock(&lock)
        latestPixelBuffer = outputBuffer
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textureRegistry?.textureFrameAvailable(self.textureId)
        }
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        os_unfair_lock_lock(&lock)
        let buffer = latestPixelBuffer
        os_unfair_lock_unlock(&lock)
        guard let pixelBuffer = buffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }

    func unregister() {
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
            textureId = -1
        }
        os_unfair_lock_lock(&lock)
        latestPixelBuffer = nil
        os_unfair_lock_unlock(&lock)
        pixelBufferPool = nil
        poolWidth = 0
        poolHeight = 0
        textureRegistry = nil
        print("Flutter texture unregistered")
    }

    private func makeRenderedPreviewImage(
        capturedImage: CVPixelBuffer,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CIImage {
        let image = CIImage(cvPixelBuffer: capturedImage)
        let extent = image.extent.integral
        let normalizeInput = CGAffineTransform(
            scaleX: 1.0 / extent.width,
            y: 1.0 / extent.height
        )
        let scaleToOutput = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
        let verticalFlip = CGAffineTransform(translationX: 0, y: viewportSize.height)
            .scaledBy(x: 1, y: -1)
        let horizontalFlip = CGAffineTransform(translationX: viewportSize.width, y: 0)
            .scaledBy(x: -1, y: 1)
        let pixelSpaceTransform = normalizeInput
            .concatenating(displayTransform)
            .concatenating(scaleToOutput)
            .concatenating(verticalFlip)
            .concatenating(horizontalFlip)

        return image.transformed(by: pixelSpaceTransform)
    }

    private func makePreviewBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard let pool = ensurePixelBufferPool(width: width, height: height) else {
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess else {
            print("Failed to create preview pixel buffer: \(status)")
            return nil
        }

        return pixelBuffer
    }

    private func ensurePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = pixelBufferPool, poolWidth == width, poolHeight == height {
            return pool
        }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let createdPool = pool else {
            print("Failed to create preview pixel buffer pool: \(status)")
            return nil
        }

        pixelBufferPool = createdPool
        poolWidth = width
        poolHeight = height
        return createdPool
    }
}
