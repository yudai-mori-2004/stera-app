import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/upload_service/data/models/list_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";

void main() {
  group("MultipartPartsResponse.fromMap", () {
    test("legacy urls string[] maps to 1-based PartUrls (backward compatible)", () {
      final r = MultipartPartsResponse.fromMap({
        "urls": ["https://a", "https://b"],
      });
      expect(r.urls.map((e) => e.partNumber), [1, 2]);
      expect(r.urls[0].url, "https://a");
      expect(r.urls[0].expiresAt, isNull);
    });

    test("explicit parts[] carry partNumber + expiresAt and win over urls", () {
      final r = MultipartPartsResponse.fromMap({
        "urls": ["ignored"],
        "parts": [
          {
            "partNumber": 33,
            "url": "https://p33",
            "expiresAt": "2026-06-14T12:00:00.000Z",
          },
        ],
        "expiresInSeconds": 86400,
      });
      expect(r.urls.single.partNumber, 33);
      expect(r.urls.single.url, "https://p33");
      expect(r.urls.single.expiresAt, DateTime.utc(2026, 6, 14, 12));
      expect(r.expiresInSeconds, 86400);
    });

    test("legacy batch-level expiresAt is applied to every inferred PartUrl", () {
      final r = MultipartPartsResponse.fromMap({
        "urls": ["https://a"],
        "expiresAt": "2026-06-14T12:00:00.000Z",
      });
      expect(r.urls.single.expiresAt, DateTime.utc(2026, 6, 14, 12));
    });
  });

  group("PartUrl round-trips through its map (it is DB-persisted)", () {
    test("toMap → fromMap preserves fields including expiresAt", () {
      final original = PartUrl(
        partNumber: 7,
        url: "https://p7",
        expiresAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final restored = PartUrl.fromMap(original.toMap());
      expect(restored.partNumber, 7);
      expect(restored.url, "https://p7");
      expect(restored.expiresAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test("a legacy map without expiresAt parses with a null expiry", () {
      final restored = PartUrl.fromMap({"partNumber": 1, "url": "https://x"});
      expect(restored.expiresAt, isNull);
    });
  });

  group("ListPartsResponse.fromMap", () {
    test("parses parts with quote-stripped etags and sizes", () {
      final r = ListPartsResponse.fromMap({
        "parts": [
          {"partNumber": 1, "etag": "e1", "size": 67108864},
        ],
        "uploadExists": true,
      });
      expect(r.uploadExists, isTrue);
      expect(r.parts.single.partNumber, 1);
      expect(r.parts.single.etag, "e1");
      expect(r.parts.single.size, 67108864);
    });

    test("the NoSuchUpload shape exposes uploadExists/objectExists", () {
      final r = ListPartsResponse.fromMap({
        "parts": [],
        "uploadExists": false,
        "objectExists": true,
      });
      expect(r.uploadExists, isFalse);
      expect(r.objectExists, isTrue);
      expect(r.parts, isEmpty);
    });

    test("missing fields default safely (uploadExists true, empty parts)", () {
      final r = ListPartsResponse.fromMap({});
      expect(r.parts, isEmpty);
      expect(r.uploadExists, isTrue);
      expect(r.objectExists, isFalse);
    });
  });

  group("MultipartStartResponse capabilities", () {
    test("parses capabilities and answers hasCapability", () {
      final r = MultipartStartResponse.fromMap({
        "uploadId": "u1",
        "key": "k1",
        "capabilities": ["list-parts", "presign-expiry"],
      });
      expect(r.hasCapability("list-parts"), isTrue);
      expect(r.hasCapability("start-idempotent"), isFalse);
    });

    test("an older backend (no capabilities) yields an empty list, not null", () {
      final r = MultipartStartResponse.fromMap({"uploadId": "u1", "key": "k1"});
      expect(r.capabilities, isEmpty);
      expect(r.hasCapability("list-parts"), isFalse);
    });
  });
}
