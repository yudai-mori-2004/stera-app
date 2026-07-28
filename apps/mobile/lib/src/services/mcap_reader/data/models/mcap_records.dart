import "dart:typed_data";

/// Parsed MCAP Schema record (opcode 0x03).
class McapSchema {
  final int id;
  final String name;
  final String encoding;
  final String definition;

  const McapSchema({
    required this.id,
    required this.name,
    required this.encoding,
    required this.definition,
  });
}

/// Parsed MCAP Channel record (opcode 0x04).
class McapChannel {
  final int id;
  final int schemaId;
  final String topic;
  final String messageEncoding;

  const McapChannel({
    required this.id,
    required this.schemaId,
    required this.topic,
    required this.messageEncoding,
  });
}

/// Parsed MCAP ChunkIndex record (opcode 0x08) from the summary section.
class McapChunkIndex {
  final int messageStartTimeNs;
  final int messageEndTimeNs;
  final int chunkStartOffset;
  final int chunkLength;

  /// channelId → absolute file offset of that channel's MessageIndex record
  /// for this chunk.
  final Map<int, int> messageIndexOffsets;
  final String compression;

  const McapChunkIndex({
    required this.messageStartTimeNs,
    required this.messageEndTimeNs,
    required this.chunkStartOffset,
    required this.chunkLength,
    required this.messageIndexOffsets,
    required this.compression,
  });
}

/// Parsed MCAP MetadataIndex record (opcode 0x0D).
class McapMetadataIndex {
  final int offset;
  final int length;
  final String name;

  const McapMetadataIndex({
    required this.offset,
    required this.length,
    required this.name,
  });
}

/// Parsed MCAP Statistics record (opcode 0x0B).
class McapStatistics {
  final int messageCount;
  final int messageStartTimeNs;
  final int messageEndTimeNs;
  final Map<int, int> channelMessageCounts;

  const McapStatistics({
    required this.messageCount,
    required this.messageStartTimeNs,
    required this.messageEndTimeNs,
    required this.channelMessageCounts,
  });
}

/// One topic as presented to the UI: channel + schema + stats.
class McapTopicInfo {
  final McapChannel channel;
  final McapSchema? schema;
  final int messageCount;
  final int startTimeNs;
  final int endTimeNs;

  const McapTopicInfo({
    required this.channel,
    required this.schema,
    required this.messageCount,
    required this.startTimeNs,
    required this.endTimeNs,
  });

  String get topic => channel.topic;
  String get schemaName => schema?.name ?? "unknown";

  double get durationSeconds =>
      endTimeNs > startTimeNs ? (endTimeNs - startTimeNs) / 1e9 : 0;

  /// Average message rate; 0 when the topic has fewer than 2 messages.
  double get frequencyHz {
    if (messageCount < 2 || durationSeconds <= 0) return 0;
    return (messageCount - 1) / durationSeconds;
  }
}

/// Location of a single message inside the file: (logTime, absolute offset of
/// the Message record). Offsets point directly into uncompressed chunk data.
class McapMessageRef {
  final int logTimeNs;
  final int fileOffset;

  const McapMessageRef({required this.logTimeNs, required this.fileOffset});
}

/// A fully-read message: header fields + raw (CDR) payload bytes.
class McapMessage {
  final int channelId;
  final int sequence;
  final int logTimeNs;
  final int publishTimeNs;
  final Uint8List payload;

  const McapMessage({
    required this.channelId,
    required this.sequence,
    required this.logTimeNs,
    required this.publishTimeNs,
    required this.payload,
  });
}
