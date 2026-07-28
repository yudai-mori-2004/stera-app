import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/presign/presign_manager.dart";

/// Records the part numbers it was asked to presign and returns a URL per part,
/// expiring [ttl] from [issuedAt].
class _RecordingFetcher {
  _RecordingFetcher({required this.issuedAt});
  final DateTime issuedAt;
  final Duration ttl = const Duration(days: 1);
  final List<List<int>> calls = [];

  PartUrlFetcher get fetch =>
      ({required String key, required String uploadId, int? partCount, List<int>? partNumbers}) async {
        calls.add(partNumbers ?? const []);
        final expiresAt = issuedAt.add(ttl);
        return (
          MultipartPartsResponse(
            urls: [
              for (final n in partNumbers ?? const <int>[])
                PartUrl(partNumber: n, url: "https://signed/$n", expiresAt: expiresAt),
            ],
          ),
          null,
        );
      };
}

void main() {
  late AppDatabase db;
  late UploadSessionDb dao;
  final now = DateTime.utc(2026, 6, 14, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UploadSessionDb(db);
  });

  tearDown(() async => db.close());

  Future<void> seed({String? s3UploadId = "u1", int parts = 3}) async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s1",
        filepath: "documents://s1.mp4",
        fileSize: parts * 100,
        fileName: "s1.mp4",
        mimeType: "video/mp4",
        state: const Value(SessionState.transferring),
        s3Key: const Value("profile/asset/clip.mp4"),
        s3UploadId: Value(s3UploadId),
      ),
    );
    await dao.insertParts([
      for (var n = 1; n <= parts; n++)
        UploadPartsCompanion.insert(
          sessionId: "s1",
          partNumber: n,
          offset: (n - 1) * 100,
          length: 100,
        ),
    ]);
  }

  Future<UploadPart> part(int n) => (db.select(
    db.uploadParts,
  )..where((p) => p.sessionId.equals("s1") & p.partNumber.equals(n))).getSingle();

  group("partsNeedingUrls", () {
    test("includes planned, excludes uploaded and fresh urlReady", () async {
      await seed();
      // part1 planned (default), part2 uploaded, part3 urlReady w/ fresh URL.
      await dao.markPartUploaded("s1", 2, etag: "e2");
      await dao.updatePart(
        "s1",
        3,
        UploadPartsCompanion(
          state: const Value(PartState.urlReady),
          url: const Value("https://fresh"),
          urlExpiresAt: Value(now.add(const Duration(hours: 5))),
        ),
      );

      final manager = PresignManager(sessionDb: dao, now: () => now);
      final needing = manager.partsNeedingUrls(await dao.getParts("s1"));
      expect(needing, [1]);
    });

    test("includes a urlReady part whose URL expires within the lead time", () async {
      await seed();
      await dao.updatePart(
        "s1",
        1,
        UploadPartsCompanion(
          state: const Value(PartState.urlReady),
          url: const Value("https://soon"),
          urlExpiresAt: Value(now.add(const Duration(minutes: 5))), // < 10 min lead
        ),
      );
      final manager = PresignManager(sessionDb: dao, now: () => now);
      expect(manager.partsNeedingUrls(await dao.getParts("s1")), contains(1));
    });
  });

  group("ensureUrls", () {
    test("fetches a batch and persists url+expiry, marking parts urlReady", () async {
      await seed();
      final fetcher = _RecordingFetcher(issuedAt: now);
      final manager = PresignManager(sessionDb: dao, fetchUrls: fetcher.fetch, now: () => now);

      final (assigned, err) = await manager.ensureUrls("s1");
      expect(err, isNull);
      expect(assigned, 3);
      final p1 = await part(1);
      expect(p1.state, PartState.urlReady);
      expect(p1.url, "https://signed/1");
      // Drift round-trips DateTime through a UTC timestamp; compare the instant,
      // not its (local vs UTC) representation.
      expect(
        p1.urlExpiresAt!.isAtSameMomentAs(now.add(const Duration(days: 1))),
        isTrue,
      );
    });

    test("never asks for more than the batch size in one round-trip", () async {
      await seed(parts: 10);
      final fetcher = _RecordingFetcher(issuedAt: now);
      final manager = PresignManager(
        sessionDb: dao,
        fetchUrls: fetcher.fetch,
        batchSize: 4,
        now: () => now,
      );

      final (assigned, _) = await manager.ensureUrls("s1");
      expect(assigned, 4);
      expect(fetcher.calls.single.length, 4);
    });

    test("is a no-op (no fetch) when every part already has a fresh URL", () async {
      await seed();
      // Give all parts fresh URLs.
      for (var n = 1; n <= 3; n++) {
        await dao.updatePart(
          "s1",
          n,
          UploadPartsCompanion(
            state: const Value(PartState.urlReady),
            url: Value("https://fresh/$n"),
            urlExpiresAt: Value(now.add(const Duration(hours: 5))),
          ),
        );
      }
      final fetcher = _RecordingFetcher(issuedAt: now);
      final manager = PresignManager(sessionDb: dao, fetchUrls: fetcher.fetch, now: () => now);

      final (assigned, err) = await manager.ensureUrls("s1");
      expect(assigned, 0);
      expect(err, isNull);
      expect(fetcher.calls, isEmpty);
    });

    test("fails cleanly when the session isn't registered yet", () async {
      await seed(s3UploadId: null);
      final manager = PresignManager(sessionDb: dao, now: () => now);
      final (assigned, err) = await manager.ensureUrls("s1");
      expect(assigned, 0);
      expect(err, isNotNull);
    });

    test("propagates a fetch Failure", () async {
      await seed();
      final manager = PresignManager(
        sessionDb: dao,
        fetchUrls:
            ({required key, required uploadId, partCount, partNumbers}) async =>
                (null, Failure.networkError()),
        now: () => now,
      );
      final (assigned, err) = await manager.ensureUrls("s1");
      expect(assigned, 0);
      expect(err, isNotNull);
    });
  });
}
