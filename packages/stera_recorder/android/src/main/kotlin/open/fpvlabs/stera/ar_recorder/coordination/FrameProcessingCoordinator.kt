package open.fpvlabs.stera.ar_recorder.coordination

import open.fpvlabs.stera.ar_recorder.encoding.FrameSampler

class FrameProcessingCoordinator(
    private val frameSampler: FrameSampler
) {
    data class EncoderIntervalStats(
        val samples: Long,
        val meanNs: Double,
        val m2Ns: Double,
        val lastSubmittedTimestampNs: Long
    )

    data class ArcoreCadenceStats(
        val samples: Long,
        val meanIntervalNs: Double,
        val m2IntervalNs: Double,
        val lastArcoreTimestampNsForEstimate: Long
    )

    data class SamplerSyncResult(
        val totalExpectedFrameCount: Long,
        val deterministicFrameIndex: Long,
        val sessionStartTimestampNs: Long
    )

    fun syncSamplerStats(): SamplerSyncResult {
        val stats = frameSampler.getDriftStats()
        return SamplerSyncResult(
            totalExpectedFrameCount = stats["totalExpectedFrameCount"] as? Long ?: 0L,
            deterministicFrameIndex = stats["deterministicFrameIndex"] as? Long ?: 0L,
            sessionStartTimestampNs = stats["sessionStartTimestampNs"] as? Long ?: Long.MIN_VALUE
        )
    }

    fun updateEncoderIntervalStats(
        timestampNs: Long,
        lastSubmittedTimestampNs: Long,
        encoderIntervalSamples: Long,
        encoderIntervalMeanNs: Double,
        encoderIntervalM2Ns: Double
    ): EncoderIntervalStats {
        if (lastSubmittedTimestampNs == Long.MIN_VALUE) {
            return EncoderIntervalStats(
                samples = encoderIntervalSamples,
                meanNs = encoderIntervalMeanNs,
                m2Ns = encoderIntervalM2Ns,
                lastSubmittedTimestampNs = timestampNs
            )
        }
        val intervalNs = (timestampNs - lastSubmittedTimestampNs).toDouble()
        val samples = encoderIntervalSamples + 1
        val delta = intervalNs - encoderIntervalMeanNs
        val mean = encoderIntervalMeanNs + delta / samples.toDouble()
        val delta2 = intervalNs - mean
        val m2 = encoderIntervalM2Ns + (delta * delta2)
        return EncoderIntervalStats(samples, mean, m2, timestampNs)
    }

    fun updateArcoreCadenceEstimate(
        arcoreTimestampNs: Long,
        lastArcoreTimestampNsForEstimate: Long,
        arcoreCadenceSamples: Long,
        arcoreCadenceMeanIntervalNs: Double,
        arcoreCadenceM2IntervalNs: Double
    ): ArcoreCadenceStats {
        if (lastArcoreTimestampNsForEstimate != Long.MIN_VALUE && arcoreTimestampNs > lastArcoreTimestampNsForEstimate) {
            val intervalNs = (arcoreTimestampNs - lastArcoreTimestampNsForEstimate).toDouble()
            val samples = arcoreCadenceSamples + 1
            val delta = intervalNs - arcoreCadenceMeanIntervalNs
            val mean = arcoreCadenceMeanIntervalNs + delta / samples.toDouble()
            val delta2 = intervalNs - mean
            val m2 = arcoreCadenceM2IntervalNs + (delta * delta2)
            return ArcoreCadenceStats(samples, mean, m2, arcoreTimestampNs)
        }
        return ArcoreCadenceStats(
            samples = arcoreCadenceSamples,
            meanIntervalNs = arcoreCadenceMeanIntervalNs,
            m2IntervalNs = arcoreCadenceM2IntervalNs,
            lastArcoreTimestampNsForEstimate = arcoreTimestampNs
        )
    }

}
