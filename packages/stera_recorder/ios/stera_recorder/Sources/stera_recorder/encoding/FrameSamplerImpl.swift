import Foundation

/// Deterministic timestamp-based RGB frame sampler.
class FrameSamplerImpl: FrameSampler {

    private var targetFps: Int
    private var encodeFrameIntervalNs: Int64
    private var sessionStartTimestampNs: Int64 = Int64.min
    private var deterministicFrameIndex: Int64 = 0
    private var totalExpectedFrameCount: Int64 = 0
    private var cumulativeTrackingPauseNs: Int64 = 0

    init(targetFps: Int = 30) {
        self.targetFps = max(targetFps, 1)
        self.encodeFrameIntervalNs = Int64(1_000_000_000 / self.targetFps)
    }

    func configure(targetFps: Int) {
        self.targetFps = max(targetFps, 1)
        self.encodeFrameIntervalNs = Int64(1_000_000_000 / self.targetFps)
    }

    func shouldEncodeFrame(timestampNs: Int64) -> Bool {
        if sessionStartTimestampNs == Int64.min {
            sessionStartTimestampNs = timestampNs
            deterministicFrameIndex = 0
            totalExpectedFrameCount = 0
        }
        let elapsedNs = max(timestampNs - sessionStartTimestampNs - cumulativeTrackingPauseNs, 0)
        let expectedFramesByNow = (elapsedNs / encodeFrameIntervalNs) + 1

        if expectedFramesByNow > totalExpectedFrameCount {
            totalExpectedFrameCount = expectedFramesByNow
        }
        if expectedFramesByNow <= deterministicFrameIndex {
            return false
        }
        deterministicFrameIndex = expectedFramesByNow
        return true
    }

    func recordTrackingPauseOffset(offsetNs: Int64) {
        cumulativeTrackingPauseNs += max(offsetNs, 0)
    }

    func reset() {
        sessionStartTimestampNs = Int64.min
        deterministicFrameIndex = 0
        totalExpectedFrameCount = 0
        cumulativeTrackingPauseNs = 0
    }

    func getDriftStats() -> [String: Any] {
        return [
            "sessionStartTimestampNs": sessionStartTimestampNs,
            "deterministicFrameIndex": deterministicFrameIndex,
            "totalExpectedFrameCount": totalExpectedFrameCount,
            "cumulativeTrackingPauseNs": cumulativeTrackingPauseNs,
            "targetFps": targetFps,
            "encodeFrameIntervalNs": encodeFrameIntervalNs
        ]
    }
}
