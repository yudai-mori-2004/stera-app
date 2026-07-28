import Foundation

class StorageManagerImpl: StorageManager {

    private let safetyFactor: Double
    private let videoBitrateBitsPerSecond: Int64
    private let depthBytesPerSecondEstimate: Int64
    private let pointCloudBytesPerSecondEstimate: Int64
    private let csvLogBytesPerSecondEstimate: Int64

    init(
        safetyFactor: Double = 0.8,
        videoBitrateBitsPerSecond: Int64 = 10_000_000,
        depthBytesPerSecondEstimate: Int64 = 2_500_000,
        pointCloudBytesPerSecondEstimate: Int64 = 250_000,
        csvLogBytesPerSecondEstimate: Int64 = 150_000
    ) {
        self.safetyFactor = safetyFactor
        self.videoBitrateBitsPerSecond = videoBitrateBitsPerSecond
        self.depthBytesPerSecondEstimate = depthBytesPerSecondEstimate
        self.pointCloudBytesPerSecondEstimate = pointCloudBytesPerSecondEstimate
        self.csvLogBytesPerSecondEstimate = csvLogBytesPerSecondEstimate
    }

    func verifyHeadroom(baseDir: URL, durationSeconds: Int64, includeDepth: Bool) -> (Bool, String?) {
        let availableBytes: Int64
        if let values = try? baseDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            availableBytes = capacity
        } else if let values = try? baseDir.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                  let capacity = values.volumeAvailableCapacity {
            availableBytes = Int64(capacity)
        } else {
            return (false, "Unable to determine available storage")
        }

        let estimatedBytes = estimateDatasetSize(durationSeconds: durationSeconds, includeDepth: includeDepth)
        let thresholdBytes = Int64(Double(availableBytes) * safetyFactor)

        if estimatedBytes > thresholdBytes {
            let message = "Insufficient storage headroom. Estimated \(estimatedBytes) bytes exceeds \(Int(safetyFactor * 100))% of available storage \(availableBytes) bytes"
            return (false, message)
        }
        return (true, nil)
    }

    func estimateDatasetSize(durationSeconds: Int64, includeDepth: Bool) -> Int64 {
        let videoBytes = (videoBitrateBitsPerSecond / 8) * durationSeconds
        let depthBytes = includeDepth ? depthBytesPerSecondEstimate * durationSeconds : 0
        let pointCloudBytes = pointCloudBytesPerSecondEstimate * durationSeconds
        let logsBytes = csvLogBytesPerSecondEstimate * durationSeconds
        return videoBytes + depthBytes + pointCloudBytes + logsBytes
    }
}
