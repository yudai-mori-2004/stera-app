import Foundation

// Under SwiftPM the @try/@catch shim is its own module, because a SwiftPM target
// can't mix Objective-C and Swift. Under CocoaPods it arrives via the pod's
// umbrella header, so there is nothing to import.
#if SWIFT_PACKAGE
import stera_recorder_objc
#endif

/// MCAP file writer with chunked mode for indexed output.
/// Implements the MCAP v0 specification: https://mcap.dev/spec
///
/// Messages are buffered and flushed as Chunk records with MessageIndex records,
/// producing an indexed file with ChunkIndex records in the summary section.
/// Foxglove and other tools can then efficiently seek and random-access the data.
class MCAPWriter {

    // MARK: - MCAP Opcodes

    private static let opHeader: UInt8        = 0x01
    private static let opFooter: UInt8        = 0x02
    private static let opSchema: UInt8        = 0x03
    private static let opChannel: UInt8       = 0x04
    private static let opMessage: UInt8       = 0x05
    private static let opChunk: UInt8         = 0x06
    private static let opMessageIndex: UInt8  = 0x07
    private static let opChunkIndex: UInt8    = 0x08
    private static let opStatistics: UInt8    = 0x0B
    private static let opMetadata: UInt8      = 0x0C
    private static let opMetadataIndex: UInt8 = 0x0D
    private static let opSummaryOffset: UInt8 = 0x0E
    private static let opDataEnd: UInt8       = 0x0F

    private static let magic: [UInt8] = [0x89, 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A]

    /// Flush chunk when buffer exceeds 512 KB to reduce peak memory.
    private static let chunkFlushThreshold = 524_288

    // MARK: - Chunk Index Info

    private struct ChunkIndexInfo {
        let messageStartTime: UInt64
        let messageEndTime: UInt64
        let chunkStartOffset: UInt64
        let chunkLength: UInt64
        let messageIndexOffsets: [UInt16: UInt64]
        let messageIndexLength: UInt64
        let compression: String
        let compressedSize: UInt64
        let uncompressedSize: UInt64
    }

    private struct MetadataIndexInfo {
        let offset: UInt64
        let length: UInt64
        let name: String
    }

    // MARK: - State

    private var fileHandle: FileHandle?
    private var offset: UInt64 = 0
    private var messageCount: UInt64 = 0
    private var messageStartTime: UInt64 = UInt64.max
    private var messageEndTime: UInt64 = 0
    private var channelMessageCounts: [UInt16: UInt64] = [:]

    /// All public mutating + reading methods take this lock around the
    /// mutable state below. Callers may invoke `addMessage` from
    /// THREE concurrent dispatch queues (wide-encode, UW-encode, and the
    /// AVCaptureDataOutputSynchronizer delegate that also drives depth +
    /// IMU drain writes). Without serialization,
    /// `chunkBuffer.append` and the chunk-offset bookkeeping interleave
    /// bytes from different records, producing the "Chunk records length
    /// exceeds remaining record size" / "Message log time did not match
    /// message index entry" corruption observed downstream.
    private var lock = os_unfair_lock()

    func getMessageStartTimeNs() -> UInt64? {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return messageStartTime == UInt64.max ? nil : messageStartTime
    }
    func getMessageEndTimeNs() -> UInt64? {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return messageEndTime == 0 ? nil : messageEndTime
    }

    // Stored for summary replay
    private var schemaRecords: [Data] = []
    private var channelRecords: [Data] = []
    private var schemaCount: UInt16 = 0
    private var channelCount: UInt16 = 0

    // Chunk buffering
    private var chunkBuffer = Data()
    private var chunkStartTime: UInt64 = UInt64.max
    private var chunkEndTime: UInt64 = 0
    private var chunkMessageOffsets: [UInt16: [(logTime: UInt64, offset: UInt64)]] = [:]

    // Summary tracking
    private var chunkIndices: [ChunkIndexInfo] = []
    private var metadataIndices: [MetadataIndexInfo] = []
    private var metadataCount: UInt32 = 0

    private var isFinalized = false

    /// When false, `addMessage` skips the implausible-logTime rejection below.
    /// Live recording keeps the guard (logTimes are current-uptime ns); the
    /// face-blur rewriter must disable it because it replays logTimes captured
    /// on an earlier boot, which can legitimately exceed 2× the current uptime.
    private var validateLogTimes = true

    // MARK: - Open / Close

    /// Opens an MCAP file for writing. Creates the file if it doesn't exist.
    func open(
        url: URL,
        profile: String = "ros2",
        library: String = "fpv_labs",
        validateLogTimes: Bool = true
    ) -> Bool {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        self.validateLogTimes = validateLogTimes
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: url) else { return false }
        fileHandle = fh
        offset = 0
        chunkBuffer.reserveCapacity(Self.chunkFlushThreshold)

        // Magic
        writeRaw(Data(Self.magic))

        // Header record
        var content = MCAPBuffer()
        content.writeString(profile)
        content.writeString(library)
        writeRecord(opcode: Self.opHeader, content: content.data)

        return true
    }

    // MARK: - Schema

    /// Registers a schema and returns its ID (1-based).
    @discardableResult
    func addSchema(name: String, encoding: String, data: String) -> UInt16 {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        schemaCount += 1
        let id = schemaCount

        var content = MCAPBuffer()
        content.writeUInt16(id)
        content.writeString(name)
        content.writeString(encoding)
        let schemaBytes = Data(data.utf8)
        content.writeUInt32(UInt32(schemaBytes.count))
        content.writeRawBytes(schemaBytes)

        let recordData = buildRecord(opcode: Self.opSchema, content: content.data)
        schemaRecords.append(recordData)
        writeRaw(recordData)
        return id
    }

    // MARK: - Channel

    /// Registers a channel and returns its ID (1-based).
    @discardableResult
    func addChannel(
        topic: String,
        messageEncoding: String,
        schemaId: UInt16,
        metadata: [String: String] = [:]
    ) -> UInt16 {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        channelCount += 1
        let id = channelCount

        var content = MCAPBuffer()
        content.writeUInt16(id)
        content.writeUInt16(schemaId)
        content.writeString(topic)
        content.writeString(messageEncoding)
        content.writeMap(metadata)

        let recordData = buildRecord(opcode: Self.opChannel, content: content.data)
        channelRecords.append(recordData)
        writeRaw(recordData)
        channelMessageCounts[id] = 0
        return id
    }

    // MARK: - Message

    /// Buffers a message. Automatically flushes as a Chunk when buffer exceeds threshold.
    func addMessage(channelId: UInt16, logTime: UInt64, publishTime: UInt64, data: Data) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard !isFinalized else { return }

        // Reject implausibly-large logTimes. ARFrame.timestamp and
        // CMDeviceMotion.timestamp are monotonic uptime nanoseconds — a normal
        // value is at most a few days' worth (≈10¹⁴ ns). A caller passing
        // `Date().timeIntervalSince1970 * 1e9` (epoch ns, ≈10¹⁸) would corrupt
        // `messageEndTime`, which in turn makes `mcapDurationMs` ~55 years and
        // poisons `metadata.json["session_duration_seconds"]`.
        if validateLogTimes {
            let uptimeNs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            let implausibleThresholdNs = uptimeNs &* 2  // 2× uptime — generous
            if logTime > implausibleThresholdNs && implausibleThresholdNs > 0 {
                print("MCAPWriter: rejecting addMessage on channel \(channelId) with implausible logTime=\(logTime) (uptimeNs=\(uptimeNs))")
                return
            }
        }

        // Build only the fixed 22-byte message header (channel/seq/time); the
        // payload is appended straight to the chunk buffer so it is copied once
        // here rather than three times (content → record → chunk). The record's
        // content length is known up front, so no intermediate record Data is
        // needed. Layout: opcode(1) + len(u64) + [channel(u16) seq(u32)
        // logTime(u64) publishTime(u64) payload].
        var header = MCAPBuffer()
        header.writeUInt16(channelId)
        header.writeUInt32(UInt32(messageCount & 0xFFFFFFFF)) // sequence
        header.writeUInt64(logTime)
        header.writeUInt64(publishTime)

        // Track offset within the chunk buffer for MessageIndex
        let offsetInChunk = UInt64(chunkBuffer.count)
        chunkBuffer.append(Self.opMessage)
        var contentLen = UInt64(header.data.count + data.count).littleEndian
        withUnsafeBytes(of: &contentLen) { chunkBuffer.append(contentsOf: $0) }
        chunkBuffer.append(header.data)
        chunkBuffer.append(data)

        chunkMessageOffsets[channelId, default: []].append((logTime: logTime, offset: offsetInChunk))

        // Update chunk time range
        if logTime < chunkStartTime { chunkStartTime = logTime }
        if logTime > chunkEndTime { chunkEndTime = logTime }

        // Update global stats
        messageCount += 1
        channelMessageCounts[channelId, default: 0] += 1
        if logTime < messageStartTime { messageStartTime = logTime }
        if logTime > messageEndTime { messageEndTime = logTime }

        // Flush if buffer exceeds threshold
        if chunkBuffer.count >= Self.chunkFlushThreshold {
            flushChunk()
        }
    }

    // MARK: - Metadata

    /// Writes a metadata record to the data section and tracks it for MetadataIndex.
    func addMetadata(name: String, metadata: [String: String]) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard !isFinalized else { return }

        // Flush any buffered messages before metadata
        if !chunkBuffer.isEmpty {
            flushChunk()
        }

        var content = MCAPBuffer()
        content.writeString(name)
        content.writeMap(metadata)

        let recordData = buildRecord(opcode: Self.opMetadata, content: content.data)
        let recordOffset = offset
        writeRaw(recordData)

        metadataIndices.append(MetadataIndexInfo(
            offset: recordOffset,
            length: UInt64(recordData.count),
            name: name
        ))
        metadataCount += 1
    }

    /// Re-emits a Metadata record whose content bytes were captured verbatim
    /// from another MCAP file (name + map already serialized). The face-blur
    /// rewriter uses this so re-serialization can't reorder the embedded map
    /// entries or perturb the JSON payloads inside (`session_metadata`,
    /// calibrations, world maps). `name` must match the name encoded in
    /// `content` — it is only used for the MetadataIndex.
    func addMetadataRaw(name: String, content: Data) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard !isFinalized else { return }

        if !chunkBuffer.isEmpty {
            flushChunk()
        }

        let recordData = buildRecord(opcode: Self.opMetadata, content: content)
        let recordOffset = offset
        writeRaw(recordData)

        metadataIndices.append(MetadataIndexInfo(
            offset: recordOffset,
            length: UInt64(recordData.count),
            name: name
        ))
        metadataCount += 1
    }

    // MARK: - Finalize

    /// Finalizes the MCAP file: flushes remaining messages, writes summary, footer, and trailing magic.
    func finish() {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard !isFinalized, let fh = fileHandle else { return }
        isFinalized = true
        let finishStart = CFAbsoluteTimeGetCurrent()

        // Flush any remaining buffered messages
        if !chunkBuffer.isEmpty {
            print("MCAPWriter: finish - flushing final chunk (\(chunkBuffer.count) bytes buffered)")
            let flushStart = CFAbsoluteTimeGetCurrent()
            flushChunk()
            let flushElapsed = CFAbsoluteTimeGetCurrent() - flushStart
            print("MCAPWriter: finish - flushChunk done in \(String(format: "%.2f", flushElapsed))s")
        }

        // DataEnd record
        var dataEndContent = MCAPBuffer()
        dataEndContent.writeUInt32(0) // data_section_crc (0 = not computed)
        writeRecord(opcode: Self.opDataEnd, content: dataEndContent.data)

        let summaryStart = offset
        let summaryWriteStart = CFAbsoluteTimeGetCurrent()

        // Summary: replay schemas
        let schemasStart = offset
        for record in schemaRecords {
            writeRaw(record)
        }
        let schemasLength = offset - schemasStart

        // Summary: replay channels
        let channelsStart = offset
        for record in channelRecords {
            writeRaw(record)
        }
        let channelsLength = offset - channelsStart

        // Summary: ChunkIndex records
        let chunkIndicesStart = offset
        for info in chunkIndices {
            writeChunkIndex(info)
        }
        let chunkIndicesLength = offset - chunkIndicesStart

        // Summary: MetadataIndex records
        let metadataIndicesStart = offset
        for info in metadataIndices {
            writeMetadataIndex(info)
        }
        let metadataIndicesLength = offset - metadataIndicesStart

        // Summary: Statistics
        let statsStart = offset
        writeStatistics()
        let statsLength = offset - statsStart

        // Summary Offset section
        let summaryOffsetStart = offset
        if schemasLength > 0 {
            writeSummaryOffset(groupOpcode: Self.opSchema, groupStart: schemasStart, groupLength: schemasLength)
        }
        if channelsLength > 0 {
            writeSummaryOffset(groupOpcode: Self.opChannel, groupStart: channelsStart, groupLength: channelsLength)
        }
        if chunkIndicesLength > 0 {
            writeSummaryOffset(groupOpcode: Self.opChunkIndex, groupStart: chunkIndicesStart, groupLength: chunkIndicesLength)
        }
        if metadataIndicesLength > 0 {
            writeSummaryOffset(groupOpcode: Self.opMetadataIndex, groupStart: metadataIndicesStart, groupLength: metadataIndicesLength)
        }
        if statsLength > 0 {
            writeSummaryOffset(groupOpcode: Self.opStatistics, groupStart: statsStart, groupLength: statsLength)
        }

        let summaryElapsed = CFAbsoluteTimeGetCurrent() - summaryWriteStart
        print("MCAPWriter: finish - summary written in \(String(format: "%.2f", summaryElapsed))s (schemas=\(schemaRecords.count), channels=\(channelRecords.count), chunkIndices=\(chunkIndices.count), messages=\(messageCount))")

        // Footer
        var footerContent = MCAPBuffer()
        footerContent.writeUInt64(summaryStart)
        footerContent.writeUInt64(summaryOffsetStart)
        footerContent.writeUInt32(0) // summary_crc (not computed)
        writeRecord(opcode: Self.opFooter, content: footerContent.data)

        // Trailing magic
        writeRaw(Data(Self.magic))

        let syncStart = CFAbsoluteTimeGetCurrent()
        print("MCAPWriter: finish - synchronizeFile starting (total file size=\(offset) bytes)")
        let syncEx = ObjCTryBlock { fh.synchronizeFile() }
        if let syncEx = syncEx {
            print("MCAPWriter: synchronizeFile failed — \(syncEx.name): \(syncEx.reason ?? "")")
        }
        let syncElapsed = CFAbsoluteTimeGetCurrent() - syncStart
        print("MCAPWriter: finish - synchronizeFile done in \(String(format: "%.2f", syncElapsed))s")
        let closeEx = ObjCTryBlock { fh.closeFile() }
        if let closeEx = closeEx {
            print("MCAPWriter: closeFile failed — \(closeEx.name): \(closeEx.reason ?? "")")
        }
        fileHandle = nil

        let totalElapsed = CFAbsoluteTimeGetCurrent() - finishStart
        print("MCAPWriter: finish - total elapsed \(String(format: "%.2f", totalElapsed))s")
    }

    /// Returns total bytes written so far.
    var bytesWritten: UInt64 {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return offset
    }

    /// Forces currently buffered messages to be emitted as a Chunk record immediately.
    /// Useful for near-real-time visibility of MCAP growth during recording.
    func forceFlushChunk() {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard !isFinalized, !writeError else { return }
        guard !chunkBuffer.isEmpty else { return }
        flushChunk()
        if let fh = fileHandle {
            let ex = ObjCTryBlock { fh.synchronizeFile() }
            if let ex = ex {
                writeError = true
                print("MCAPWriter: forceFlushChunk synchronizeFile failed — \(ex.name): \(ex.reason ?? "")")
            }
        }
    }

    // MARK: - Chunk Flushing

    private func flushChunk() {
        guard !chunkBuffer.isEmpty else { return }

        let uncompressedSize = UInt64(chunkBuffer.count)
        let chunkRecordStart = offset

        // Build Chunk record content
        var chunkContent = MCAPBuffer()
        chunkContent.writeUInt64(chunkStartTime)
        chunkContent.writeUInt64(chunkEndTime)
        chunkContent.writeUInt64(uncompressedSize) // uncompressed_size
        chunkContent.writeUInt32(0) // uncompressed_crc (not computed)
        chunkContent.writeString("") // compression: empty = none
        // records: length-prefixed bytes
        chunkContent.writeUInt64(uncompressedSize)
        chunkContent.writeRawBytes(chunkBuffer)

        writeRecord(opcode: Self.opChunk, content: chunkContent.data)
        let chunkRecordLength = offset - chunkRecordStart

        // Write MessageIndex records (one per channel that had messages in this chunk)
        let messageIndexStart = offset
        var messageIndexOffsets: [UInt16: UInt64] = [:]

        for (channelId, entries) in chunkMessageOffsets.sorted(by: { $0.key < $1.key }) {
            messageIndexOffsets[channelId] = offset

            var indexContent = MCAPBuffer()
            indexContent.writeUInt16(channelId)
            // records: array of (log_time, offset) tuples, length-prefixed
            var entriesBuf = MCAPBuffer()
            for entry in entries {
                entriesBuf.writeUInt64(entry.logTime)
                entriesBuf.writeUInt64(entry.offset)
            }
            indexContent.writeUInt32(UInt32(entriesBuf.data.count))
            indexContent.writeRawBytes(entriesBuf.data)

            writeRecord(opcode: Self.opMessageIndex, content: indexContent.data)
        }
        let messageIndexLength = offset - messageIndexStart

        // Store ChunkIndex info for summary
        chunkIndices.append(ChunkIndexInfo(
            messageStartTime: chunkStartTime,
            messageEndTime: chunkEndTime,
            chunkStartOffset: chunkRecordStart,
            chunkLength: chunkRecordLength,
            messageIndexOffsets: messageIndexOffsets,
            messageIndexLength: messageIndexLength,
            compression: "",
            compressedSize: uncompressedSize,
            uncompressedSize: uncompressedSize
        ))

        // Reset chunk state. Pre-size the next chunk buffer to the flush
        // threshold so it doesn't reallocate repeatedly as it fills.
        chunkBuffer = Data()
        chunkBuffer.reserveCapacity(Self.chunkFlushThreshold)
        chunkStartTime = UInt64.max
        chunkEndTime = 0
        chunkMessageOffsets = [:]
    }

    // MARK: - Summary Record Writers

    private func writeChunkIndex(_ info: ChunkIndexInfo) {
        var content = MCAPBuffer()
        content.writeUInt64(info.messageStartTime)
        content.writeUInt64(info.messageEndTime)
        content.writeUInt64(info.chunkStartOffset)
        content.writeUInt64(info.chunkLength)
        // message_index_offsets: Map<uint16, uint64>
        var mapBuf = MCAPBuffer()
        for (channelId, idxOffset) in info.messageIndexOffsets.sorted(by: { $0.key < $1.key }) {
            mapBuf.writeUInt16(channelId)
            mapBuf.writeUInt64(idxOffset)
        }
        content.writeUInt32(UInt32(mapBuf.data.count))
        content.writeRawBytes(mapBuf.data)
        content.writeUInt64(info.messageIndexLength)
        content.writeString(info.compression)
        content.writeUInt64(info.compressedSize)
        content.writeUInt64(info.uncompressedSize)

        writeRecord(opcode: Self.opChunkIndex, content: content.data)
    }

    private func writeMetadataIndex(_ info: MetadataIndexInfo) {
        var content = MCAPBuffer()
        content.writeUInt64(info.offset)
        content.writeUInt64(info.length)
        content.writeString(info.name)

        writeRecord(opcode: Self.opMetadataIndex, content: content.data)
    }

    private func writeSummaryOffset(groupOpcode: UInt8, groupStart: UInt64, groupLength: UInt64) {
        var content = MCAPBuffer()
        content.writeUInt8(groupOpcode)
        content.writeUInt64(groupStart)
        content.writeUInt64(groupLength)

        writeRecord(opcode: Self.opSummaryOffset, content: content.data)
    }

    private func writeStatistics() {
        var content = MCAPBuffer()
        content.writeUInt64(messageCount)
        content.writeUInt16(schemaCount)
        content.writeUInt32(UInt32(channelCount))
        content.writeUInt32(0) // attachment_count
        content.writeUInt32(metadataCount) // metadata_count
        content.writeUInt32(UInt32(chunkIndices.count)) // chunk_count
        content.writeUInt64(messageStartTime == UInt64.max ? 0 : messageStartTime)
        content.writeUInt64(messageEndTime)
        // channel_message_counts: Map<uint16, uint64>
        var mapBuf = MCAPBuffer()
        for (channelId, count) in channelMessageCounts.sorted(by: { $0.key < $1.key }) {
            mapBuf.writeUInt16(channelId)
            mapBuf.writeUInt64(count)
        }
        content.writeUInt32(UInt32(mapBuf.data.count))
        content.writeRawBytes(mapBuf.data)

        writeRecord(opcode: Self.opStatistics, content: content.data)
    }

    // MARK: - Low-Level Record Writing

    private func buildRecord(opcode: UInt8, content: Data) -> Data {
        var record = Data()
        record.append(opcode)
        var len = UInt64(content.count).littleEndian
        record.append(UnsafeBufferPointer(start: &len, count: 1))
        record.append(content)
        return record
    }

    private func writeRecord(opcode: UInt8, content: Data) {
        let record = buildRecord(opcode: opcode, content: content)
        writeRaw(record)
    }

    private(set) var writeError: Bool = false

    private func writeRaw(_ data: Data) {
        guard !writeError, let fh = fileHandle else { return }
        let ex = ObjCTryBlock { fh.write(data) }
        if let ex = ex {
            writeError = true
            print("MCAPWriter: write failed — \(ex.name): \(ex.reason ?? "")")
            return
        }
        offset += UInt64(data.count)
    }
}

// MARK: - MCAP Buffer

/// Buffer for building MCAP record content with proper serialization.
struct MCAPBuffer {
    private(set) var data = Data()

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeUInt32(_ value: UInt32) {
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeUInt64(_ value: UInt64) {
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    /// Writes an MCAP string: uint32 byte-length + UTF-8 bytes (no null terminator, unlike CDR).
    mutating func writeString(_ value: String) {
        let utf8 = Data(value.utf8)
        writeUInt32(UInt32(utf8.count))
        data.append(utf8)
    }

    /// Writes a Map<string, string>: uint32 total byte length, then key-value pairs.
    mutating func writeMap(_ map: [String: String]) {
        var inner = Data()
        for (key, value) in map {
            let keyUtf8 = Data(key.utf8)
            var keyLen = UInt32(keyUtf8.count).littleEndian
            inner.append(UnsafeBufferPointer(start: &keyLen, count: 1))
            inner.append(keyUtf8)
            let valUtf8 = Data(value.utf8)
            var valLen = UInt32(valUtf8.count).littleEndian
            inner.append(UnsafeBufferPointer(start: &valLen, count: 1))
            inner.append(valUtf8)
        }
        writeUInt32(UInt32(inner.count))
        data.append(inner)
    }

    mutating func writeRawBytes(_ bytes: Data) {
        data.append(bytes)
    }
}
