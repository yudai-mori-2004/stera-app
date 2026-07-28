/// One entry in a frozen chunk plan: a contiguous byte range of the source file
/// that becomes one multipart part.
class ChunkPlanEntry {
  const ChunkPlanEntry({
    required this.partNumber,
    required this.offset,
    required this.length,
  });

  /// 1-based (S3 part-number convention).
  final int partNumber;
  final int offset;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is ChunkPlanEntry &&
      other.partNumber == partNumber &&
      other.offset == offset &&
      other.length == length;

  @override
  int get hashCode => Object.hash(partNumber, offset, length);

  @override
  String toString() =>
      "ChunkPlanEntry(part: $partNumber, offset: $offset, length: $length)";
}

/// Splits a file into a uniform-part-size chunk plan.
///
/// R2/S3 require every part except the last to be the same size, so the plan is
/// `chunkSize`-uniform with the final part holding the remainder. The plan is
/// computed once at `preparing` and frozen on the session row — resume never
/// recomputes it, so a chunk-size change in code can never split an in-flight
/// upload differently.
abstract final class UploadChunkPlanner {
  static List<ChunkPlanEntry> plan({
    required int fileSize,
    required int chunkSize,
  }) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, "chunkSize", "must be > 0");
    }
    if (fileSize <= 0) return const [];

    final parts = <ChunkPlanEntry>[];
    var offset = 0;
    var partNumber = 1;
    while (offset < fileSize) {
      final remaining = fileSize - offset;
      final length = remaining < chunkSize ? remaining : chunkSize;
      parts.add(
        ChunkPlanEntry(partNumber: partNumber, offset: offset, length: length),
      );
      offset += length;
      partNumber++;
    }
    return parts;
  }

  /// Part count without materialising the plan.
  static int partCountFor({required int fileSize, required int chunkSize}) {
    if (fileSize <= 0 || chunkSize <= 0) return 0;
    return (fileSize + chunkSize - 1) ~/ chunkSize;
  }
}
