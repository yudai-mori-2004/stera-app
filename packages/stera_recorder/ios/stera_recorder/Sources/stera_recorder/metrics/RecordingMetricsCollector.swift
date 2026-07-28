import Foundation

struct TimestampWindow {
    let minNs: Int64
    let maxNs: Int64
    let count: Int64
}

struct AssociationStats {
    let associated: Int
    let unmatched: Int
    let maxDeltaNs: Int64
}

protocol RecordingMetricsCollector {
    func computeDepthAssociations(
        rgbTimestamps: [Int64],
        depthTimestamps: [Int64],
        thresholdNs: Int64
    ) -> AssociationStats

    func computeStreamOverlap(ranges: [TimestampWindow]) -> Bool
}
