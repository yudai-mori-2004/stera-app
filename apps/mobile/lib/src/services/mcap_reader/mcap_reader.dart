import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";

/// Pure-Dart reader for the MCAP files produced by the app's own recorder
/// (`ios/Runner/ar_recorder/data/MCAPWriter.swift`): chunked, indexed,
/// **uncompressed** MCAP v0 with a full summary section.
///
/// Reads the footer + summary for the topic list, then uses ChunkIndex /
/// MessageIndex records for random access to individual messages, so opening
/// a multi-GB file never loads more than the summary plus one message.
///
/// Requires a finalized file (trailing magic + footer present). All file IO
/// is serialized internally — callers may share one instance across widgets.
class McapReader {
  McapReader._(this._file, this._fileLength);

  static const List<int> _magic = [0x89, 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A];

  static const int _opSchema = 0x03;
  static const int _opChannel = 0x04;
  static const int _opMessage = 0x05;
  static const int _opMessageIndex = 0x07;
  static const int _opChunkIndex = 0x08;
  static const int _opStatistics = 0x0B;
  static const int _opMetadataIndex = 0x0D;

  final RandomAccessFile _file;
  final int _fileLength;

  /// Serializes async ops on [_file] — RandomAccessFile forbids concurrent use.
  Future<void> _ioChain = Future.value();

  final Map<int, McapSchema> schemas = {};
  final Map<int, McapChannel> channels = {};
  final List<McapChunkIndex> chunkIndexes = [];
  final List<McapMetadataIndex> metadataIndexes = [];
  McapStatistics? statistics;

  /// Chunk records-section base offsets, lazily resolved per chunk start
  /// offset (message-index offsets are relative to this base).
  final Map<int, int> _chunkRecordsBase = {};

  bool _closed = false;

  /// Opens and parses the summary section. Throws [McapReadException] when the
  /// file is missing, not finalized, or structurally invalid.
  static Future<McapReader> open(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const McapReadException("MCAP file not found");
    }
    final length = await file.length();
    final raf = await file.open();
    final reader = McapReader._(raf, length);
    try {
      await reader._parseSummary();
      return reader;
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _synchronized(() => _file.close());
  }

  /// Topics with at least one message, sorted by name.
  List<McapTopicInfo> get topics {
    final stats = statistics;
    final result = <McapTopicInfo>[];
    for (final channel in channels.values) {
      final count = stats?.channelMessageCounts[channel.id] ?? 0;
      if (count == 0) continue;
      var start = 0x7FFFFFFFFFFFFFFF;
      var end = 0;
      for (final chunk in chunkIndexes) {
        if (!chunk.messageIndexOffsets.containsKey(channel.id)) continue;
        if (chunk.messageStartTimeNs < start) start = chunk.messageStartTimeNs;
        if (chunk.messageEndTimeNs > end) end = chunk.messageEndTimeNs;
      }
      result.add(
        McapTopicInfo(
          channel: channel,
          schema: schemas[channel.schemaId],
          messageCount: count,
          startTimeNs: end == 0 ? 0 : start,
          endTimeNs: end,
        ),
      );
    }
    result.sort((a, b) => a.topic.compareTo(b.topic));
    return result;
  }

  /// Builds the full (logTime, fileOffset) index for one channel by reading
  /// the MessageIndex records of every chunk that contains it. Sorted by
  /// logTime.
  Future<List<McapMessageRef>> buildTopicIndex(int channelId) async {
    final refs = <McapMessageRef>[];
    for (final chunk in chunkIndexes) {
      final indexOffset = chunk.messageIndexOffsets[channelId];
      if (indexOffset == null) continue;
      final recordsBase = await _recordsBaseForChunk(chunk);
      final record = await _readRecordAt(indexOffset, expectedOpcode: _opMessageIndex);
      final buf = _BufReader(record);
      buf.uint16(); // channel id (already known)
      final entriesLen = buf.uint32();
      final entriesEnd = buf.offset + entriesLen;
      while (buf.offset < entriesEnd) {
        final logTime = buf.uint64();
        final offsetInChunk = buf.uint64();
        refs.add(
          McapMessageRef(
            logTimeNs: logTime,
            fileOffset: recordsBase + offsetInChunk,
          ),
        );
      }
    }
    refs.sort((a, b) => a.logTimeNs.compareTo(b.logTimeNs));
    return refs;
  }

  /// Reads the full Message record at [ref] (header + raw CDR payload).
  Future<McapMessage> readMessage(McapMessageRef ref) async {
    final record = await _readRecordAt(ref.fileOffset, expectedOpcode: _opMessage);
    if (record.length < 22) {
      throw const McapReadException("Message record too short");
    }
    final buf = _BufReader(record);
    final channelId = buf.uint16();
    final sequence = buf.uint32();
    final logTime = buf.uint64();
    final publishTime = buf.uint64();
    return McapMessage(
      channelId: channelId,
      sequence: sequence,
      logTimeNs: logTime,
      publishTimeNs: publishTime,
      payload: Uint8List.sublistView(record, buf.offset),
    );
  }

  /// Reads a Metadata record's string map given its index entry.
  Future<Map<String, String>> readMetadata(McapMetadataIndex index) async {
    final record = await _readRecordAt(index.offset, expectedOpcode: 0x0C);
    final buf = _BufReader(record);
    buf.mcapString(); // name (already known from the index)
    return buf.stringMap();
  }

  // ---------------------------------------------------------------------
  // Summary parsing
  // ---------------------------------------------------------------------

  Future<void> _parseSummary() async {
    // 8 magic + minimal header on one end, footer record (29) + magic (8) on
    // the other.
    if (_fileLength < 8 + 29 + 8) {
      throw const McapReadException("File too small to be a valid MCAP");
    }

    final head = await _readAt(0, 8);
    if (!_bytesEqual(head, _magic)) {
      throw const McapReadException("Not an MCAP file (bad leading magic)");
    }
    final tail = await _readAt(_fileLength - 8, 8);
    if (!_bytesEqual(tail, _magic)) {
      throw const McapReadException(
        "Recording is not finalized (missing trailing magic)",
      );
    }

    // Footer record: opcode(1) + len(8) + summaryStart(8) + summaryOffsetStart(8) + crc(4).
    final footer = await _readAt(_fileLength - 8 - 29, 29);
    final footerBuf = _BufReader(footer);
    final footerOpcode = footerBuf.uint8();
    final footerLen = footerBuf.uint64();
    if (footerOpcode != 0x02 || footerLen != 20) {
      throw const McapReadException("Invalid MCAP footer");
    }
    final summaryStart = footerBuf.uint64();
    if (summaryStart == 0 || summaryStart >= _fileLength - 8 - 29) {
      throw const McapReadException("MCAP has no summary section");
    }

    final summaryBytes = await _readAt(
      summaryStart,
      _fileLength - 8 - 29 - summaryStart,
    );
    final buf = _BufReader(summaryBytes);
    while (buf.remaining >= 9) {
      final opcode = buf.uint8();
      final length = buf.uint64();
      if (length > buf.remaining) break;
      final content = _BufReader(buf.bytes(length));
      switch (opcode) {
        case _opSchema:
          final id = content.uint16();
          final name = content.mcapString();
          final encoding = content.mcapString();
          final defLen = content.uint32();
          final definition = content.utf8Bytes(defLen);
          schemas[id] = McapSchema(
            id: id,
            name: name,
            encoding: encoding,
            definition: definition,
          );
        case _opChannel:
          final id = content.uint16();
          final schemaId = content.uint16();
          final topic = content.mcapString();
          final messageEncoding = content.mcapString();
          channels[id] = McapChannel(
            id: id,
            schemaId: schemaId,
            topic: topic,
            messageEncoding: messageEncoding,
          );
        case _opChunkIndex:
          final startTime = content.uint64();
          final endTime = content.uint64();
          final chunkStartOffset = content.uint64();
          final chunkLength = content.uint64();
          final mapLen = content.uint32();
          final mapEnd = content.offset + mapLen;
          final offsets = <int, int>{};
          while (content.offset < mapEnd) {
            final channelId = content.uint16();
            offsets[channelId] = content.uint64();
          }
          content.uint64(); // message index length
          final compression = content.mcapString();
          chunkIndexes.add(
            McapChunkIndex(
              messageStartTimeNs: startTime,
              messageEndTimeNs: endTime,
              chunkStartOffset: chunkStartOffset,
              chunkLength: chunkLength,
              messageIndexOffsets: offsets,
              compression: compression,
            ),
          );
        case _opMetadataIndex:
          final offset = content.uint64();
          final recordLength = content.uint64();
          final name = content.mcapString();
          metadataIndexes.add(
            McapMetadataIndex(offset: offset, length: recordLength, name: name),
          );
        case _opStatistics:
          final messageCount = content.uint64();
          content.uint16(); // schema count
          content.uint32(); // channel count
          content.uint32(); // attachment count
          content.uint32(); // metadata count
          content.uint32(); // chunk count
          final startTime = content.uint64();
          final endTime = content.uint64();
          final mapLen = content.uint32();
          final mapEnd = content.offset + mapLen;
          final counts = <int, int>{};
          while (content.offset < mapEnd) {
            final channelId = content.uint16();
            counts[channelId] = content.uint64();
          }
          statistics = McapStatistics(
            messageCount: messageCount,
            messageStartTimeNs: startTime,
            messageEndTimeNs: endTime,
            channelMessageCounts: counts,
          );
        default:
          break; // SummaryOffset and anything unknown: skip
      }
    }

    final unsupported = chunkIndexes
        .where((c) => c.compression.isNotEmpty)
        .map((c) => c.compression)
        .toSet();
    if (unsupported.isNotEmpty) {
      throw McapReadException(
        "Unsupported chunk compression: ${unsupported.join(", ")}",
      );
    }
  }

  // ---------------------------------------------------------------------
  // Random access helpers
  // ---------------------------------------------------------------------

  /// Absolute file offset where a chunk's (uncompressed) records section
  /// starts. MessageIndex entry offsets are relative to this base.
  Future<int> _recordsBaseForChunk(McapChunkIndex chunk) async {
    final cached = _chunkRecordsBase[chunk.chunkStartOffset];
    if (cached != null) return cached;

    // Chunk record: opcode(1) len(8), then content: start(8) end(8)
    // uncompressedSize(8) crc(4) compression(4+n) recordsLen(8) records...
    final header = await _readAt(chunk.chunkStartOffset, 64);
    final buf = _BufReader(header);
    final opcode = buf.uint8();
    if (opcode != 0x06) {
      throw const McapReadException("ChunkIndex does not point at a Chunk record");
    }
    buf.uint64(); // record length
    buf.uint64(); // message start time
    buf.uint64(); // message end time
    buf.uint64(); // uncompressed size
    buf.uint32(); // uncompressed crc
    final compressionLen = buf.uint32();
    final base =
        chunk.chunkStartOffset + 9 + 28 + 4 + compressionLen + 8;
    _chunkRecordsBase[chunk.chunkStartOffset] = base;
    return base;
  }

  /// Reads one record at [offset], returning its content bytes.
  Future<Uint8List> _readRecordAt(int offset, {required int expectedOpcode}) async {
    final header = await _readAt(offset, 9);
    final buf = _BufReader(header);
    final opcode = buf.uint8();
    final length = buf.uint64();
    if (opcode != expectedOpcode) {
      throw McapReadException(
        "Unexpected record opcode 0x${opcode.toRadixString(16)} at $offset",
      );
    }
    if (length < 0 || offset + 9 + length > _fileLength) {
      throw const McapReadException("Record extends past end of file");
    }
    return _readAt(offset + 9, length);
  }

  Future<Uint8List> _readAt(int offset, int length) {
    return _synchronized(() async {
      if (_closed) throw const McapReadException("Reader is closed");
      await _file.setPosition(offset);
      final bytes = await _file.read(length);
      if (bytes.length < length) {
        throw const McapReadException("Unexpected end of file");
      }
      return bytes;
    });
  }

  Future<T> _synchronized<T>(Future<T> Function() op) {
    final result = _ioChain.then((_) => op());
    _ioChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static bool _bytesEqual(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class McapReadException implements Exception {
  final String message;
  const McapReadException(this.message);

  @override
  String toString() => message;
}

/// Little-endian cursor over an in-memory buffer (MCAP record layout — no
/// CDR alignment; see CdrDeserializer for message payloads).
class _BufReader {
  _BufReader(this._data)
      : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  int offset = 0;

  int get remaining => _data.length - offset;

  int uint8() => _view.getUint8(offset++);

  int uint16() {
    final v = _view.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int uint32() {
    final v = _view.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int uint64() {
    final v = _view.getUint64(offset, Endian.little);
    offset += 8;
    return v;
  }

  Uint8List bytes(int length) {
    final v = Uint8List.sublistView(_data, offset, offset + length);
    offset += length;
    return v;
  }

  String utf8Bytes(int length) {
    return utf8.decode(bytes(length), allowMalformed: true);
  }

  /// MCAP string: uint32 byte length + UTF-8 bytes (no null terminator).
  String mcapString() {
    final length = uint32();
    return utf8Bytes(length);
  }

  /// MCAP `Map<string, string>`: uint32 total byte length, then k/v pairs.
  Map<String, String> stringMap() {
    final totalLen = uint32();
    final end = offset + totalLen;
    final map = <String, String>{};
    while (offset < end) {
      final key = mcapString();
      final value = mcapString();
      map[key] = value;
    }
    return map;
  }
}
