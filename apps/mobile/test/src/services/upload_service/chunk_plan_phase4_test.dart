import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_sizer.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_planner.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_disk_preflight.dart";

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

void main() {
  group("UploadChunkSizer.chooseChunkSize", () {
    test("adaptive sizing within the 16–64 MiB bounds", () {
      expect(UploadChunkSizer.chooseChunkSize(500 * _mib), 16 * _mib);
      expect(UploadChunkSizer.chooseChunkSize(2 * _gib), 16 * _mib);
      expect(UploadChunkSizer.chooseChunkSize(10 * _gib), 24 * _mib);
      // 40 GB / 600 ≈ 72 MiB raw → clamped to the 64 MiB max.
      expect(UploadChunkSizer.chooseChunkSize(40 * _gib), 64 * _mib);
      expect(UploadChunkSizer.maxChunk, 64 * _mib);
      expect(UploadChunkSizer.minChunk, 16 * _mib);
    });

    test("clamps small files to the 16 MiB min, mid/large to the 64 MiB max", () {
      expect(UploadChunkSizer.chooseChunkSize(1 * _mib), UploadChunkSizer.minChunk);
      expect(UploadChunkSizer.chooseChunkSize(0), UploadChunkSizer.minChunk);
      // 60 GiB / 600 ≈ 104 MiB raw → clamped to the 64 MiB adaptive max.
      expect(UploadChunkSizer.chooseChunkSize(60 * _gib), UploadChunkSizer.maxChunk);
    });

    test("files over 60 GiB use a fixed 128 MiB part", () {
      expect(UploadChunkSizer.hugeFileChunk, 128 * _mib);
      // 40–60 GiB stay on the adaptive (64 MiB) tier; just over → 128 MiB.
      expect(UploadChunkSizer.chooseChunkSize(40 * _gib), 64 * _mib);
      expect(UploadChunkSizer.chooseChunkSize(60 * _gib), 64 * _mib);
      expect(UploadChunkSizer.chooseChunkSize(61 * _gib), 128 * _mib);
      expect(UploadChunkSizer.chooseChunkSize(100 * _gib), 128 * _mib);
    });

    test("adaptive tier is always 8 MiB-aligned within [16, 64] MiB", () {
      for (final gb in [1, 5, 15, 25, 50, 60]) {
        final c = UploadChunkSizer.chooseChunkSize(gb * _gib);
        expect(c % (8 * _mib), 0, reason: "${gb}GB chunk not 8MiB-aligned");
        expect(c, greaterThanOrEqualTo(UploadChunkSizer.minChunk));
        expect(c, lessThanOrEqualTo(UploadChunkSizer.maxChunk));
      }
    });

    test("keeps every file size well under R2's 10k part ceiling", () {
      for (final gb in [2, 10, 40, 60, 100, 600]) {
        final size = gb * _gib;
        final parts = UploadChunkPlanner.partCountFor(
          fileSize: size,
          chunkSize: UploadChunkSizer.chooseChunkSize(size),
        );
        expect(parts, lessThan(10000));
      }
    });
  });

  group("UploadDiskPreflight", () {
    test("required bytes are the window, not a whole-file copy", () {
      // 50 GB upload at 72 MiB chunks, window 8 → ~576 MiB, NOT ~50 GB.
      final required = UploadDiskPreflight.requiredBytes(
        chunkSize: 72 * _mib,
        windowSize: 8,
      );
      expect(required, 8 * 72 * _mib);
      expect(required, lessThan(1 * _gib));
    });

    test("headroom check passes with enough free disk, fails when tight", () {
      bool fits(int availableBytes) => UploadDiskPreflight.hasHeadroom(
        availableBytes: availableBytes,
        chunkSize: 72 * _mib,
        windowSize: 8,
        slackBytes: 72 * _mib,
      );
      expect(fits(1 * _gib), isTrue); // 1 GB free, needs ~648 MiB
      expect(fits(500 * _mib), isFalse); // 500 MB free, not enough
    });
  });
}
