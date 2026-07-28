import Foundation
import ARKit
import simd
import Accelerate

/// Extracts pose, point cloud, depth, and intrinsics from ARKit frames.
class ArFrameProcessorImpl: ArFrameProcessor {

    private var pointCloudBufferAllocations: Int = 0
    private var depthBufferAllocations: Int = 0
    private var pointCloudAcquireCount: Int = 0
    private var pointCloudReleaseCount: Int = 0
    private var depthImageAcquireCount: Int = 0
    private var depthImageCloseCount: Int = 0
    private var meshBufferAllocations: Int = 0

    /// Tracks which feature point identifiers were present in the previous frame.
    /// Used to filter out stale accumulated points that may have pre-relocalization coordinates.
    private var previousFrameIdentifiers: Set<UInt64> = []

    /// Reusable Float working buffer for depth conversion. Depth maps are a fixed
    /// resolution per session, so this is allocated once and reused every frame
    /// instead of churning a ~200KB heap allocation per depth frame. Safe because
    /// all extraction runs on the serial `ar.frame.processing` queue.
    private var depthScratch: [Float] = []

    func resetAllocationCounters() {
        pointCloudBufferAllocations = 0
        depthBufferAllocations = 0
        meshBufferAllocations = 0
        pointCloudAcquireCount = 0
        pointCloudReleaseCount = 0
        depthImageAcquireCount = 0
        depthImageCloseCount = 0
        previousFrameIdentifiers = []
    }

    func prepareForRecording() {
        resetAllocationCounters()
    }

    func getPointCloudBufferAllocations() -> Int { pointCloudBufferAllocations }
    func getDepthBufferAllocations() -> Int { depthBufferAllocations }
    func getMeshBufferAllocations() -> Int { meshBufferAllocations }
    func getPointCloudAcquireCount() -> Int { pointCloudAcquireCount }
    func getPointCloudReleaseCount() -> Int { pointCloudReleaseCount }
    func getDepthImageAcquireCount() -> Int { depthImageAcquireCount }
    func getDepthImageCloseCount() -> Int { depthImageCloseCount }

    /// Extracts camera pose as [tx, ty, tz, qx, qy, qz, qw].
    /// Uses simd_quatf from the camera transform matrix.
    func extractPose(camera: ARCamera) -> [Float] {
        let transform = camera.transform
        let translation = transform.columns.3
        let quaternion = simd_quatf(transform)

        return [
            translation.x,
            translation.y,
            translation.z,
            quaternion.imag.x,
            quaternion.imag.y,
            quaternion.imag.z,
            quaternion.real
        ]
    }

    /// Extracts tracking state as a string.
    func extractTrackingState(camera: ARCamera) -> String {
        switch camera.trackingState {
        case .normal:
            return ArTrackingState.tracking.rawValue
        case .limited:
            return ArTrackingState.paused.rawValue
        case .notAvailable:
            return ArTrackingState.stopped.rawValue
        }
    }

    /// Extracts point cloud data as binary, filtering out stale accumulated feature points.
    /// Format: [timestamp_ns: Int64][numPoints: Int32] followed by [x, y, z, confidence: Float32] * N
    /// ARKit rawFeaturePoints has no per-point confidence, so we use 1.0 default.
    ///
    /// ARKit's rawFeaturePoints accumulates feature points across the session. After a
    /// relocalization or tracking correction, mesh anchor transforms are updated but
    /// previously-reported feature point positions are NOT retroactively corrected.
    /// We filter to only include points whose identifiers are present in the current frame,
    /// ensuring stale pre-relocalization points are excluded.
    func extractPointCloudFrame(frame: ARFrame, timestampNs: Int64) -> PointCloudFrameData? {
        guard let featurePoints = frame.rawFeaturePoints else { return nil }
        pointCloudAcquireCount += 1

        let allPoints = featurePoints.points
        let identifiers = featurePoints.identifiers
        let totalCount = allPoints.count

        if totalCount == 0 {
            pointCloudReleaseCount += 1
            return nil
        }

        // Build the set of identifiers present in the current frame
        let currentIdentifiers = Set(identifiers)

        // On the first frame, accept all points. On subsequent frames, only include
        // points whose identifiers are in the current frame's set (filtering out stale
        // accumulated points that may have pre-relocalization coordinates).
        let filteredIndices: [Int]
        if previousFrameIdentifiers.isEmpty {
            // First frame — accept everything
            filteredIndices = Array(0..<totalCount)
        } else {
            // Only keep points present in the current frame's identifier set
            filteredIndices = (0..<totalCount).filter { currentIdentifiers.contains(identifiers[$0]) }
        }

        // Update tracked identifiers for next frame
        previousFrameIdentifiers = currentIdentifiers

        let numPoints = filteredIndices.count
        if numPoints == 0 {
            pointCloudReleaseCount += 1
            return nil
        }

        // 8 bytes timestamp + 4 bytes count + (4 floats * 4 bytes) per point
        let bufferSize = 8 + 4 + (numPoints * 4 * 4)
        var data = Data(count: bufferSize)
        pointCloudBufferAllocations += 1

        data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }

            // Header: timestamp (Int64) + point count (Int32). iOS is little-endian,
            // so native stores already produce the little-endian byte layout the
            // reader expects (offsets 0/8/12 are correctly aligned for malloc'd Data).
            base.storeBytes(of: timestampNs, toByteOffset: 0, as: Int64.self)
            (base + 8).storeBytes(of: Int32(numPoints), toByteOffset: 0, as: Int32.self)

            // Points: x, y, z, confidence written as native Float32 (little-endian
            // on-device), one typed store each instead of four 4-byte memcpy calls.
            let floatPtr = (base + 12).assumingMemoryBound(to: Float.self)
            let confidence: Float = 1.0
            var w = 0
            for idx in filteredIndices {
                let point = allPoints[idx]
                floatPtr[w]     = point.x
                floatPtr[w + 1] = point.y
                floatPtr[w + 2] = point.z
                floatPtr[w + 3] = confidence
                w += 4
            }
        }

        // Bounding box is diagnostic only — compute it on the logging cadence rather
        // than on every point of every frame.
        if pointCloudAcquireCount % 30 == 0 {
            var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
            var minY: Float = .greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude
            var minZ: Float = .greatestFiniteMagnitude, maxZ: Float = -.greatestFiniteMagnitude
            for idx in filteredIndices {
                let p = allPoints[idx]
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
                minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
            }
            print("[PointCloud] pts=\(numPoints)/\(totalCount) bbox x[\(String(format: "%.2f", minX)),\(String(format: "%.2f", maxX))] y[\(String(format: "%.2f", minY)),\(String(format: "%.2f", maxY))] z[\(String(format: "%.2f", minZ)),\(String(format: "%.2f", maxZ))]")
        }

        pointCloudReleaseCount += 1

        return PointCloudFrameData(
            bytes: data,
            validSize: bufferSize,
            pointCount: numPoints
        )
    }

    /// Extracts depth image from ARKit smoothedSceneDepth (LiDAR devices only).
    /// Converts Float32 meters to UInt16 millimeters (little-endian), matching Android format.
    func extractDepthImage(frame: ARFrame) -> DepthFrameData? {
        guard let sceneDepth = frame.smoothedSceneDepth else { return nil }
        depthImageAcquireCount += 1

        return autoreleasepool {
            let depthMap = sceneDepth.depthMap
            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let bytesPerPixel = 2  // UInt16 output

            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                depthImageCloseCount += 1
                return nil
            }

            let rowStride = CVPixelBufferGetBytesPerRow(depthMap)
            let srcRowStride = rowStride / MemoryLayout<Float>.size
            let pixelCount = width * height
            let expectedSize = pixelCount * bytesPerPixel
            var packedDepth = Data(count: expectedSize)
            depthBufferAllocations += 1

            // Convert meters → mm directly from the locked depth map into a reused
            // scratch buffer, fusing the row-pack copy and the ×1000 scale into one
            // vDSP pass (no per-frame intermediate allocation).
            let srcPtr = baseAddress.assumingMemoryBound(to: Float.self)
            if depthScratch.count != pixelCount {
                depthScratch = [Float](repeating: 0, count: pixelCount)
            }
            var scale: Float = 1000.0
            depthScratch.withUnsafeMutableBufferPointer { dst in
                let dstBase = dst.baseAddress!
                if srcRowStride == width {
                    // Contiguous source: single fused copy+scale pass.
                    vDSP_vsmul(srcPtr, 1, &scale, dstBase, 1, vDSP_Length(pixelCount))
                } else {
                    // Strided source rows: scale row-by-row straight from the source.
                    for y in 0..<height {
                        vDSP_vsmul(srcPtr + y * srcRowStride, 1, &scale,
                                   dstBase + y * width, 1, vDSP_Length(width))
                    }
                }
            }

            // clamp 0-65535, convert to UInt16
            var lo: Float = 0.0
            var hi: Float = 65535.0
            vDSP_vclip(depthScratch, 1, &lo, &hi, &depthScratch, 1, vDSP_Length(pixelCount))

            packedDepth.withUnsafeMutableBytes { rawBuffer in
                guard let dstPtr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt16.self) else { return }
                vDSP_vfixu16(depthScratch, 1, dstPtr, 1, vDSP_Length(pixelCount))
            }

            depthImageCloseCount += 1

            return DepthFrameData(
                bytes: packedDepth,
                validSize: expectedSize,
                width: width,
                height: height,
                bytesPerPixel: bytesPerPixel,
                pixelStride: bytesPerPixel,
                rowStride: width * bytesPerPixel,
                unit: "millimeters"
            )
        }
    }

    /// Extracts mesh reconstruction data from ARMeshAnchors (LiDAR devices only).
    /// Produces structured world-space vertices and triangle indices directly,
    /// avoiding a binary serialize→deserialize round-trip.
    func extractMeshData(anchors: [ARAnchor], timestampNs: Int64) -> MeshFrameData? {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        if meshAnchors.isEmpty { return nil }

        var totalVertexCount = 0
        var totalFaceCount = 0
        for anchor in meshAnchors {
            totalVertexCount += anchor.geometry.vertices.count
            totalFaceCount += anchor.geometry.faces.count
        }

        var worldVertices: [(Double, Double, Double)] = []
        worldVertices.reserveCapacity(totalVertexCount)
        var triangles: [(UInt32, UInt32, UInt32)] = []
        triangles.reserveCapacity(totalFaceCount)
        meshBufferAllocations += 1

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let t = anchor.transform
            let vertexOffset = UInt32(worldVertices.count)

            // Read vertices from Metal buffer and apply world transform
            let vertexSource = geometry.vertices
            let vertexCount = vertexSource.count
            let vertexBuffer = vertexSource.buffer
            let vertexStride = vertexSource.stride
            let vertexBaseOffset = vertexSource.offset
            let vertexPtr = vertexBuffer.contents().advanced(by: vertexBaseOffset)

            for i in 0..<vertexCount {
                let vPtr = vertexPtr.advanced(by: i * vertexStride)
                let vx = vPtr.assumingMemoryBound(to: Float.self)[0]
                let vy = vPtr.advanced(by: 4).assumingMemoryBound(to: Float.self).pointee
                let vz = vPtr.advanced(by: 8).assumingMemoryBound(to: Float.self).pointee

                // Apply anchor transform (column-major 4x4)
                let dvx = Double(vx)
                let dvy = Double(vy)
                let dvz = Double(vz)
                let wx = Double(t.columns.0.x) * dvx + Double(t.columns.1.x) * dvy + Double(t.columns.2.x) * dvz + Double(t.columns.3.x)
                let wy = Double(t.columns.0.y) * dvx + Double(t.columns.1.y) * dvy + Double(t.columns.2.y) * dvz + Double(t.columns.3.y)
                let wz = Double(t.columns.0.z) * dvx + Double(t.columns.1.z) * dvy + Double(t.columns.2.z) * dvz + Double(t.columns.3.z)
                worldVertices.append((wx, wy, wz))
            }

            // Read face indices
            let faceElement = geometry.faces
            let faceCount = faceElement.count
            let indexBuffer = faceElement.buffer
            let bytesPerIndex = faceElement.bytesPerIndex
            let indexPtr = indexBuffer.contents()
            let indicesPerFace = faceElement.indexCountPerPrimitive

            for i in 0..<faceCount {
                var indices: [UInt32] = []
                indices.reserveCapacity(indicesPerFace)
                for j in 0..<indicesPerFace {
                    let idxOffset = (i * indicesPerFace + j) * bytesPerIndex
                    let rawPtr = indexPtr.advanced(by: idxOffset)
                    let index: UInt32
                    if bytesPerIndex == 4 {
                        index = rawPtr.assumingMemoryBound(to: UInt32.self).pointee
                    } else if bytesPerIndex == 2 {
                        index = UInt32(rawPtr.assumingMemoryBound(to: UInt16.self).pointee)
                    } else {
                        index = UInt32(rawPtr.assumingMemoryBound(to: UInt8.self).pointee)
                    }
                    indices.append(index + vertexOffset)
                }
                if indices.count >= 3 {
                    triangles.append((indices[0], indices[1], indices[2]))
                }
            }
        }

        return MeshFrameData(
            bytes: Data(),
            validSize: 0,
            anchorCount: meshAnchors.count,
            totalVertexCount: totalVertexCount,
            totalFaceCount: totalFaceCount,
            worldVertices: worldVertices,
            triangles: triangles
        )
    }

    /// Extracts depth camera intrinsics by scaling RGB intrinsics to depth resolution.
    func extractDepthIntrinsics(camera: ARCamera, depthWidth: Int, depthHeight: Int) -> [String: Any]? {
        if depthWidth == 0 || depthHeight == 0 { return nil }

        let rgbIntrinsics = camera.intrinsics
        let rgbW = Double(camera.imageResolution.width)
        let rgbH = Double(camera.imageResolution.height)
        if rgbW == 0 || rgbH == 0 { return nil }

        let scaleX = Double(depthWidth) / rgbW
        let scaleY = Double(depthHeight) / rgbH

        return [
            "focalLengthX": Double(rgbIntrinsics[0][0]) * scaleX,
            "focalLengthY": Double(rgbIntrinsics[1][1]) * scaleY,
            "principalPointX": Double(rgbIntrinsics[2][0]) * scaleX,
            "principalPointY": Double(rgbIntrinsics[2][1]) * scaleY,
            "imageWidth": depthWidth,
            "imageHeight": depthHeight
        ]
    }

    /// Extracts camera intrinsics.
    /// Uses pixel buffer dimensions (always landscape) rather than camera.imageResolution
    /// (which reflects device UI orientation and may return portrait dimensions).
    func extractIntrinsics(camera: ARCamera, pixelBuffer: CVPixelBuffer) -> [String: Any] {
        let intrinsics = camera.intrinsics
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        return [
            "focalLengthX": intrinsics[0][0],
            "focalLengthY": intrinsics[1][1],
            "principalPointX": intrinsics[2][0],
            "principalPointY": intrinsics[2][1],
            "imageWidth": width,
            "imageHeight": height
        ]
    }
}
