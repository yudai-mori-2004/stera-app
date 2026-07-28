import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_planner.dart";

void main() {
  group("UploadChunkPlanner.plan", () {
    test("splits into uniform parts with a remainder last part", () {
      final parts = UploadChunkPlanner.plan(fileSize: 250, chunkSize: 100);
      expect(parts, [
        const ChunkPlanEntry(partNumber: 1, offset: 0, length: 100),
        const ChunkPlanEntry(partNumber: 2, offset: 100, length: 100),
        const ChunkPlanEntry(partNumber: 3, offset: 200, length: 50),
      ]);
    });

    test("an exact multiple has no remainder part", () {
      final parts = UploadChunkPlanner.plan(fileSize: 300, chunkSize: 100);
      expect(parts.length, 3);
      expect(parts.last.length, 100);
    });

    test("a file smaller than one chunk is a single part", () {
      final parts = UploadChunkPlanner.plan(fileSize: 40, chunkSize: 100);
      expect(parts, [const ChunkPlanEntry(partNumber: 1, offset: 0, length: 40)]);
    });

    test("covers the whole file with no gaps or overlaps", () {
      const fileSize = 40 * 1024 * 1024 * 1024; // 40 GB
      const chunkSize = 72 * 1024 * 1024; // 72 MiB
      final parts = UploadChunkPlanner.plan(fileSize: fileSize, chunkSize: chunkSize);

      expect(parts.first.offset, 0);
      var covered = 0;
      for (var i = 0; i < parts.length; i++) {
        expect(parts[i].partNumber, i + 1);
        expect(parts[i].offset, covered);
        covered += parts[i].length;
      }
      expect(covered, fileSize);
      expect(parts.length, UploadChunkPlanner.partCountFor(fileSize: fileSize, chunkSize: chunkSize));
    });

    test("empty file yields no parts; zero chunkSize throws", () {
      expect(UploadChunkPlanner.plan(fileSize: 0, chunkSize: 100), isEmpty);
      expect(
        () => UploadChunkPlanner.plan(fileSize: 100, chunkSize: 0),
        throwsArgumentError,
      );
    });
  });
}
