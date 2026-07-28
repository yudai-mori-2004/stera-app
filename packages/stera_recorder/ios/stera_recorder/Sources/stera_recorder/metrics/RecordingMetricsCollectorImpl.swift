import Foundation

class RecordingMetricsCollectorImpl: RecordingMetricsCollector {

    func computeDepthAssociations(
        rgbTimestamps: [Int64],
        depthTimestamps: [Int64],
        thresholdNs: Int64
    ) -> AssociationStats {
        if rgbTimestamps.isEmpty || depthTimestamps.isEmpty {
            return AssociationStats(associated: 0, unmatched: rgbTimestamps.count, maxDeltaNs: 0)
        }

        let sortedDepth = depthTimestamps.sorted()
        var associated = 0
        var maxDeltaNs: Int64 = 0

        for rgbTs in rgbTimestamps {
            let insertionPoint = binarySearchInsertionPoint(sortedDepth, rgbTs)

            var nearestDelta: Int64 = Int64.max
            if insertionPoint < sortedDepth.count {
                nearestDelta = min(nearestDelta, abs(sortedDepth[insertionPoint] - rgbTs))
            }
            if insertionPoint > 0 {
                nearestDelta = min(nearestDelta, abs(sortedDepth[insertionPoint - 1] - rgbTs))
            }

            if nearestDelta <= thresholdNs {
                associated += 1
                if nearestDelta > maxDeltaNs {
                    maxDeltaNs = nearestDelta
                }
            }
        }

        return AssociationStats(
            associated: associated,
            unmatched: rgbTimestamps.count - associated,
            maxDeltaNs: maxDeltaNs
        )
    }

    func computeStreamOverlap(ranges: [TimestampWindow]) -> Bool {
        let validRanges = ranges.filter { $0.count > 0 }
        if validRanges.isEmpty { return false }
        let latestStart = validRanges.map { $0.minNs }.max()!
        let earliestEnd = validRanges.map { $0.maxNs }.min()!
        return latestStart <= earliestEnd
    }

    private func binarySearchInsertionPoint(_ array: [Int64], _ target: Int64) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
