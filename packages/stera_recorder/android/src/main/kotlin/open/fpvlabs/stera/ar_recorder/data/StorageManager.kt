package open.fpvlabs.stera.ar_recorder.data

import java.io.File

interface StorageManager {
    fun verifyHeadroom(
        baseDir: File,
        durationSeconds: Long,
        includeDepth: Boolean
    ): Pair<Boolean, String?>

    fun estimateDatasetSize(durationSeconds: Long, includeDepth: Boolean): Long
}
