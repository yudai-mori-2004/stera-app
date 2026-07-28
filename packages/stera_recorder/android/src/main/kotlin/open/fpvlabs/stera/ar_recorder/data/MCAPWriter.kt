package open.fpvlabs.stera.ar_recorder.data

import java.io.File
import java.io.FileOutputStream
import java.io.BufferedOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * MCAP file writer with chunked mode for indexed output.
 * Implements the MCAP v0 specification: https://mcap.dev/spec
 *
 * Messages are buffered and flushed as Chunk records with MessageIndex records,
 * producing an indexed file with ChunkIndex records in the summary section.
 * Foxglove and other tools can then efficiently seek and random-access the data.
 */
class MCAPWriter {

    private companion object {
        const val OP_HEADER: Byte = 0x01
        const val OP_FOOTER: Byte = 0x02
        const val OP_SCHEMA: Byte = 0x03
        const val OP_CHANNEL: Byte = 0x04
        const val OP_MESSAGE: Byte = 0x05
        const val OP_CHUNK: Byte = 0x06
        const val OP_MESSAGE_INDEX: Byte = 0x07
        const val OP_CHUNK_INDEX: Byte = 0x08
        const val OP_STATISTICS: Byte = 0x0B
        const val OP_METADATA: Byte = 0x0C
        const val OP_METADATA_INDEX: Byte = 0x0D
        const val OP_SUMMARY_OFFSET: Byte = 0x0E
        const val OP_DATA_END: Byte = 0x0F
        val MAGIC = byteArrayOf(0x89.toByte(), 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A)

        /** Flush chunk when buffer exceeds 1 MB. */
        const val CHUNK_FLUSH_THRESHOLD = 1_048_576
    }

    private data class ChunkIndexInfo(
        val messageStartTime: Long,
        val messageEndTime: Long,
        val chunkStartOffset: Long,
        val chunkLength: Long,
        val messageIndexOffsets: Map<Int, Long>,
        val messageIndexLength: Long,
        val compression: String,
        val compressedSize: Long,
        val uncompressedSize: Long
    )

    private data class MetadataIndexInfo(
        val offset: Long,
        val length: Long,
        val name: String
    )

    private data class MessageIndexEntry(
        val logTime: Long,
        val offset: Long
    )

    private var outputStream: BufferedOutputStream? = null
    private var offset: Long = 0
    private var messageCount: Long = 0
    private var messageStartTime: Long = Long.MAX_VALUE
    private var messageEndTime: Long = 0
    private val channelMessageCounts = mutableMapOf<Int, Long>()

    // Stored for summary replay
    private val schemaRecords = mutableListOf<ByteArray>()
    private val channelRecords = mutableListOf<ByteArray>()
    private var schemaCount: Int = 0
    private var channelCount: Int = 0

    // Chunk buffering
    private var chunkBuffer = mutableListOf<ByteArray>()
    private var chunkBufferSize = 0
    private var chunkStartTime: Long = Long.MAX_VALUE
    private var chunkEndTime: Long = 0
    private val chunkMessageOffsets = mutableMapOf<Int, MutableList<MessageIndexEntry>>()

    // Summary tracking
    private val chunkIndices = mutableListOf<ChunkIndexInfo>()
    private val metadataIndices = mutableListOf<MetadataIndexInfo>()
    private var metadataCount: Int = 0

    private var isFinalized = false

    /** Opens an MCAP file for writing. */
    fun open(file: File, profile: String = "ros2", library: String = "fpv_labs"): Boolean {
        return try {
            outputStream = BufferedOutputStream(FileOutputStream(file))
            offset = 0

            // Magic
            writeRaw(MAGIC)

            // Header record
            val content = MCAPBuffer()
            content.writeString(profile)
            content.writeString(library)
            writeRecord(OP_HEADER, content.toByteArray())
            true
        } catch (e: Exception) {
            println("Failed to open MCAP file: ${e.message}")
            false
        }
    }

    /** Registers a schema and returns its ID (1-based). */
    fun addSchema(name: String, encoding: String, data: String): Int {
        schemaCount++
        val id = schemaCount

        val content = MCAPBuffer()
        content.writeUInt16(id)
        content.writeString(name)
        content.writeString(encoding)
        val schemaBytes = data.toByteArray(Charsets.UTF_8)
        content.writeUInt32(schemaBytes.size)
        content.writeRawBytes(schemaBytes)

        val recordData = buildRecord(OP_SCHEMA, content.toByteArray())
        schemaRecords.add(recordData)
        writeRaw(recordData)
        return id
    }

    /** Registers a channel and returns its ID (1-based). */
    fun addChannel(
        topic: String,
        messageEncoding: String,
        schemaId: Int,
        metadata: Map<String, String> = emptyMap()
    ): Int {
        channelCount++
        val id = channelCount

        val content = MCAPBuffer()
        content.writeUInt16(id)
        content.writeUInt16(schemaId)
        content.writeString(topic)
        content.writeString(messageEncoding)
        content.writeMap(metadata)

        val recordData = buildRecord(OP_CHANNEL, content.toByteArray())
        channelRecords.add(recordData)
        writeRaw(recordData)
        channelMessageCounts[id] = 0
        return id
    }

    /** Buffers a message. Automatically flushes as a Chunk when buffer exceeds threshold. */
    fun addMessage(channelId: Int, logTime: Long, publishTime: Long, data: ByteArray) {
        if (isFinalized) return

        // Build the full message record in a single exact-size array, copying the
        // payload once. The content length (fixed 22-byte header + payload) is
        // known up front, so we skip the MCAPBuffer/toByteArray/buildRecord chain
        // that otherwise copies a large JPEG/depth payload several times.
        // Layout: opcode(1) + len(u64) + [channel(u16) seq(u32) logTime(u64)
        // publishTime(u64) payload].
        val seq = (messageCount and 0xFFFFFFFFL).toInt()
        val contentLen = 22 + data.size
        val recordData = ByteArray(1 + 8 + contentLen)
        ByteBuffer.wrap(recordData).order(ByteOrder.LITTLE_ENDIAN).apply {
            put(OP_MESSAGE)
            putLong(contentLen.toLong())
            putShort(channelId.toShort())
            putInt(seq)
            putLong(logTime)
            putLong(publishTime)
            put(data)
        }

        // Track offset within the chunk buffer for MessageIndex
        val offsetInChunk = chunkBufferSize.toLong()
        chunkBuffer.add(recordData)
        chunkBufferSize += recordData.size

        chunkMessageOffsets.getOrPut(channelId) { mutableListOf() }
            .add(MessageIndexEntry(logTime, offsetInChunk))

        // Update chunk time range
        if (logTime < chunkStartTime) chunkStartTime = logTime
        if (logTime > chunkEndTime) chunkEndTime = logTime

        // Update global stats
        messageCount++
        channelMessageCounts[channelId] = (channelMessageCounts[channelId] ?: 0) + 1
        if (logTime < messageStartTime) messageStartTime = logTime
        if (logTime > messageEndTime) messageEndTime = logTime

        // Flush if buffer exceeds threshold
        if (chunkBufferSize >= CHUNK_FLUSH_THRESHOLD) {
            flushChunk()
        }
    }

    /** Writes a metadata record and tracks it for MetadataIndex. */
    fun addMetadata(name: String, metadata: Map<String, String>) {
        if (isFinalized) return

        // Flush any buffered messages before metadata
        if (chunkBufferSize > 0) {
            flushChunk()
        }

        val content = MCAPBuffer()
        content.writeString(name)
        content.writeMap(metadata)

        val recordData = buildRecord(OP_METADATA, content.toByteArray())
        val recordOffset = offset
        writeRaw(recordData)

        metadataIndices.add(MetadataIndexInfo(
            offset = recordOffset,
            length = recordData.size.toLong(),
            name = name
        ))
        metadataCount++
    }

    /** Returns total bytes written so far. */
    val bytesWritten: Long get() = offset

    /**
     * Forces currently buffered messages to be emitted as a Chunk record immediately.
     * Useful for near-real-time visibility of MCAP growth during recording.
     */
    fun forceFlushChunk() {
        if (isFinalized) return
        if (chunkBufferSize == 0) return
        flushChunk()
        outputStream?.flush()
    }

    /** Finalizes the MCAP file: flushes remaining messages, writes summary, footer, and trailing magic. */
    fun finish() {
        if (isFinalized) return
        val os = outputStream ?: return
        isFinalized = true

        // Flush any remaining buffered messages
        if (chunkBufferSize > 0) {
            flushChunk()
        }

        // DataEnd
        val dataEndContent = MCAPBuffer()
        dataEndContent.writeUInt32(0) // data_section_crc
        writeRecord(OP_DATA_END, dataEndContent.toByteArray())

        val summaryStart = offset

        // Summary: replay schemas
        val schemasStart = offset
        for (record in schemaRecords) writeRaw(record)
        val schemasLength = offset - schemasStart

        // Summary: replay channels
        val channelsStart = offset
        for (record in channelRecords) writeRaw(record)
        val channelsLength = offset - channelsStart

        // Summary: ChunkIndex records
        val chunkIndicesStart = offset
        for (info in chunkIndices) writeChunkIndex(info)
        val chunkIndicesLength = offset - chunkIndicesStart

        // Summary: MetadataIndex records
        val metadataIndicesStart = offset
        for (info in metadataIndices) writeMetadataIndex(info)
        val metadataIndicesLength = offset - metadataIndicesStart

        // Summary: Statistics
        val statsStart = offset
        writeStatistics()
        val statsLength = offset - statsStart

        // Summary Offset section
        val summaryOffsetStart = offset
        if (schemasLength > 0) {
            writeSummaryOffset(OP_SCHEMA, schemasStart, schemasLength)
        }
        if (channelsLength > 0) {
            writeSummaryOffset(OP_CHANNEL, channelsStart, channelsLength)
        }
        if (chunkIndicesLength > 0) {
            writeSummaryOffset(OP_CHUNK_INDEX, chunkIndicesStart, chunkIndicesLength)
        }
        if (metadataIndicesLength > 0) {
            writeSummaryOffset(OP_METADATA_INDEX, metadataIndicesStart, metadataIndicesLength)
        }
        if (statsLength > 0) {
            writeSummaryOffset(OP_STATISTICS, statsStart, statsLength)
        }

        // Footer
        val footerContent = MCAPBuffer()
        footerContent.writeUInt64(summaryStart)
        footerContent.writeUInt64(summaryOffsetStart)
        footerContent.writeUInt32(0) // summary_crc
        writeRecord(OP_FOOTER, footerContent.toByteArray())

        // Trailing magic
        writeRaw(MAGIC)

        os.flush()
        os.close()
        outputStream = null
    }

    // --- Chunk Flushing ---

    private fun flushChunk() {
        if (chunkBufferSize == 0) return

        val uncompressedSize = chunkBufferSize.toLong()
        val chunkRecordStart = offset

        // Concatenate buffered records
        val allRecords = ByteArray(chunkBufferSize)
        var pos = 0
        for (record in chunkBuffer) {
            System.arraycopy(record, 0, allRecords, pos, record.size)
            pos += record.size
        }

        // Build Chunk record content
        val chunkContent = MCAPBuffer()
        chunkContent.writeUInt64(chunkStartTime)
        chunkContent.writeUInt64(chunkEndTime)
        chunkContent.writeUInt64(uncompressedSize) // uncompressed_size
        chunkContent.writeUInt32(0) // uncompressed_crc
        chunkContent.writeString("") // compression: empty = none
        // records: length-prefixed bytes
        chunkContent.writeUInt64(uncompressedSize)
        chunkContent.writeRawBytes(allRecords)

        writeRecord(OP_CHUNK, chunkContent.toByteArray())
        val chunkRecordLength = offset - chunkRecordStart

        // Write MessageIndex records (one per channel in this chunk)
        val messageIndexStart = offset
        val messageIndexOffsets = mutableMapOf<Int, Long>()

        for ((channelId, entries) in chunkMessageOffsets.toSortedMap()) {
            messageIndexOffsets[channelId] = offset

            val indexContent = MCAPBuffer()
            indexContent.writeUInt16(channelId)
            // records: array of (log_time, offset) tuples, length-prefixed
            val entriesBuf = MCAPBuffer()
            for (entry in entries) {
                entriesBuf.writeUInt64(entry.logTime)
                entriesBuf.writeUInt64(entry.offset)
            }
            val entriesBytes = entriesBuf.toByteArray()
            indexContent.writeUInt32(entriesBytes.size)
            indexContent.writeRawBytes(entriesBytes)

            writeRecord(OP_MESSAGE_INDEX, indexContent.toByteArray())
        }
        val messageIndexLength = offset - messageIndexStart

        // Store ChunkIndex info for summary
        chunkIndices.add(ChunkIndexInfo(
            messageStartTime = chunkStartTime,
            messageEndTime = chunkEndTime,
            chunkStartOffset = chunkRecordStart,
            chunkLength = chunkRecordLength,
            messageIndexOffsets = messageIndexOffsets.toMap(),
            messageIndexLength = messageIndexLength,
            compression = "",
            compressedSize = uncompressedSize,
            uncompressedSize = uncompressedSize
        ))

        // Reset chunk state
        chunkBuffer.clear()
        chunkBufferSize = 0
        chunkStartTime = Long.MAX_VALUE
        chunkEndTime = 0
        chunkMessageOffsets.clear()
    }

    // --- Summary Record Writers ---

    private fun writeChunkIndex(info: ChunkIndexInfo) {
        val content = MCAPBuffer()
        content.writeUInt64(info.messageStartTime)
        content.writeUInt64(info.messageEndTime)
        content.writeUInt64(info.chunkStartOffset)
        content.writeUInt64(info.chunkLength)
        // message_index_offsets: Map<uint16, uint64>
        val mapBuf = MCAPBuffer()
        for ((channelId, idxOffset) in info.messageIndexOffsets.toSortedMap()) {
            mapBuf.writeUInt16(channelId)
            mapBuf.writeUInt64(idxOffset)
        }
        val mapBytes = mapBuf.toByteArray()
        content.writeUInt32(mapBytes.size)
        content.writeRawBytes(mapBytes)
        content.writeUInt64(info.messageIndexLength)
        content.writeString(info.compression)
        content.writeUInt64(info.compressedSize)
        content.writeUInt64(info.uncompressedSize)

        writeRecord(OP_CHUNK_INDEX, content.toByteArray())
    }

    private fun writeMetadataIndex(info: MetadataIndexInfo) {
        val content = MCAPBuffer()
        content.writeUInt64(info.offset)
        content.writeUInt64(info.length)
        content.writeString(info.name)

        writeRecord(OP_METADATA_INDEX, content.toByteArray())
    }

    private fun writeSummaryOffset(groupOpcode: Byte, groupStart: Long, groupLength: Long) {
        val content = MCAPBuffer()
        content.writeRawBytes(byteArrayOf(groupOpcode))
        content.writeUInt64(groupStart)
        content.writeUInt64(groupLength)

        writeRecord(OP_SUMMARY_OFFSET, content.toByteArray())
    }

    private fun writeStatistics() {
        val content = MCAPBuffer()
        content.writeUInt64(messageCount)
        content.writeUInt16(schemaCount)
        content.writeUInt32(channelCount)
        content.writeUInt32(0) // attachment_count
        content.writeUInt32(metadataCount) // metadata_count
        content.writeUInt32(chunkIndices.size) // chunk_count
        content.writeUInt64(if (messageStartTime == Long.MAX_VALUE) 0 else messageStartTime)
        content.writeUInt64(messageEndTime)
        // channel_message_counts map
        val mapBuf = MCAPBuffer()
        for ((channelId, count) in channelMessageCounts.toSortedMap()) {
            mapBuf.writeUInt16(channelId)
            mapBuf.writeUInt64(count)
        }
        val mapBytes = mapBuf.toByteArray()
        content.writeUInt32(mapBytes.size)
        content.writeRawBytes(mapBytes)

        writeRecord(OP_STATISTICS, content.toByteArray())
    }

    // --- Low-Level Record Writing ---

    private fun buildRecord(opcode: Byte, content: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(1 + 8 + content.size).order(ByteOrder.LITTLE_ENDIAN)
        buf.put(opcode)
        buf.putLong(content.size.toLong())
        buf.put(content)
        return buf.array()
    }

    private fun writeRecord(opcode: Byte, content: ByteArray) {
        writeRaw(buildRecord(opcode, content))
    }

    private fun writeRaw(data: ByteArray) {
        outputStream?.write(data)
        offset += data.size
    }
}

/**
 * Buffer for building MCAP record content with proper little-endian serialization.
 */
class MCAPBuffer {
    private val buffer = ByteBuffer.allocate(65536).order(ByteOrder.LITTLE_ENDIAN)
    private var size = 0
    private val overflow = mutableListOf<ByteArray>()
    private var overflowSize = 0

    fun writeUInt16(value: Int) {
        ensureCapacity(2)
        buffer.putShort(size, value.toShort())
        size += 2
    }

    fun writeUInt32(value: Int) {
        ensureCapacity(4)
        buffer.putInt(size, value)
        size += 4
    }

    fun writeUInt64(value: Long) {
        ensureCapacity(8)
        buffer.putLong(size, value)
        size += 8
    }

    /** Writes an MCAP string: uint32 byte-length + UTF-8 bytes (no null terminator). */
    fun writeString(value: String) {
        val utf8 = value.toByteArray(Charsets.UTF_8)
        writeUInt32(utf8.size)
        writeRawBytes(utf8)
    }

    /** Writes a Map<string, string>. */
    fun writeMap(map: Map<String, String>) {
        val inner = MCAPBuffer()
        for ((key, v) in map) {
            inner.writeString(key)
            inner.writeString(v)
        }
        val innerBytes = inner.toByteArray()
        writeUInt32(innerBytes.size)
        writeRawBytes(innerBytes)
    }

    fun writeRawBytes(bytes: ByteArray) {
        if (size + bytes.size <= buffer.capacity()) {
            System.arraycopy(bytes, 0, buffer.array(), size, bytes.size)
            size += bytes.size
        } else {
            // Flush current buffer content to overflow
            if (size > 0) {
                overflow.add(buffer.array().copyOfRange(0, size))
                overflowSize += size
                size = 0
            }
            overflow.add(bytes.copyOf())
            overflowSize += bytes.size
        }
    }

    fun toByteArray(): ByteArray {
        if (overflow.isEmpty()) {
            return buffer.array().copyOfRange(0, size)
        }
        val result = ByteArray(overflowSize + size)
        var pos = 0
        for (chunk in overflow) {
            System.arraycopy(chunk, 0, result, pos, chunk.size)
            pos += chunk.size
        }
        if (size > 0) {
            System.arraycopy(buffer.array(), 0, result, pos, size)
        }
        return result
    }

    private fun ensureCapacity(needed: Int) {
        if (size + needed > buffer.capacity()) {
            overflow.add(buffer.array().copyOfRange(0, size))
            overflowSize += size
            size = 0
        }
    }
}
