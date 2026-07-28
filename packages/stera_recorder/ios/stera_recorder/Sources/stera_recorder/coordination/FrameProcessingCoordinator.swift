import Foundation

class FrameProcessingCoordinator {

    private let frameSampler: FrameSampler

    init(frameSampler: FrameSampler) {
        self.frameSampler = frameSampler
    }

    struct EncoderIntervalStats {
        let samples: Int64
        let meanNs: Double
        let m2Ns: Double
        let lastSubmittedTimestampNs: Int64
    }

    struct ArkitCadenceStats {
        let samples: Int64
        let meanIntervalNs: Double
        let m2IntervalNs: Double
        let lastArkitTimestampNsForEstimate: Int64
    }

    struct SamplerSyncResult {
        let totalExpectedFrameCount: Int64
        let deterministicFrameIndex: Int64
        let sessionStartTimestampNs: Int64
    }

    func syncSamplerStats() -> SamplerSyncResult {
        let stats = frameSampler.getDriftStats()
        return SamplerSyncResult(
            totalExpectedFrameCount: stats["totalExpectedFrameCount"] as? Int64 ?? 0,
            deterministicFrameIndex: stats["deterministicFrameIndex"] as? Int64 ?? 0,
            sessionStartTimestampNs: stats["sessionStartTimestampNs"] as? Int64 ?? Int64.min
        )
    }

    func updateEncoderIntervalStats(
        timestampNs: Int64,
        lastSubmittedTimestampNs: Int64,
        encoderIntervalSamples: Int64,
        encoderIntervalMeanNs: Double,
        encoderIntervalM2Ns: Double
    ) -> EncoderIntervalStats {
        if lastSubmittedTimestampNs == Int64.min {
            return EncoderIntervalStats(
                samples: encoderIntervalSamples,
                meanNs: encoderIntervalMeanNs,
                m2Ns: encoderIntervalM2Ns,
                lastSubmittedTimestampNs: timestampNs
            )
        }
        let intervalNs = Double(timestampNs - lastSubmittedTimestampNs)
        let samples = encoderIntervalSamples + 1
        let delta = intervalNs - encoderIntervalMeanNs
        let mean = encoderIntervalMeanNs + delta / Double(samples)
        let delta2 = intervalNs - mean
        let m2 = encoderIntervalM2Ns + (delta * delta2)
        return EncoderIntervalStats(samples: samples, meanNs: mean, m2Ns: m2, lastSubmittedTimestampNs: timestampNs)
    }

    func updateArkitCadenceEstimate(
        arkitTimestampNs: Int64,
        lastArkitTimestampNsForEstimate: Int64,
        arkitCadenceSamples: Int64,
        arkitCadenceMeanIntervalNs: Double,
        arkitCadenceM2IntervalNs: Double
    ) -> ArkitCadenceStats {
        if lastArkitTimestampNsForEstimate != Int64.min && arkitTimestampNs > lastArkitTimestampNsForEstimate {
            let intervalNs = Double(arkitTimestampNs - lastArkitTimestampNsForEstimate)
            let samples = arkitCadenceSamples + 1
            let delta = intervalNs - arkitCadenceMeanIntervalNs
            let mean = arkitCadenceMeanIntervalNs + delta / Double(samples)
            let delta2 = intervalNs - mean
            let m2 = arkitCadenceM2IntervalNs + (delta * delta2)
            return ArkitCadenceStats(samples: samples, meanIntervalNs: mean, m2IntervalNs: m2, lastArkitTimestampNsForEstimate: arkitTimestampNs)
        }
        return ArkitCadenceStats(
            samples: arkitCadenceSamples,
            meanIntervalNs: arkitCadenceMeanIntervalNs,
            m2IntervalNs: arkitCadenceM2IntervalNs,
            lastArkitTimestampNsForEstimate: arkitTimestampNs
        )
    }
}
