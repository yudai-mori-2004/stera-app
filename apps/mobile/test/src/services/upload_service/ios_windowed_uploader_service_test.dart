import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/upload_service/channels/ios_windowed_uploader_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("WindowedUploadEvent.fromMap", () {
    test("parses partCompleted", () {
      final e = WindowedUploadEvent.fromMap({
        "type": "partCompleted",
        "sessionId": "s1",
        "partNumber": 3,
        "etag": "etag-3",
      });
      expect(e, isA<WindowedPartCompleted>());
      final c = e as WindowedPartCompleted;
      expect(c.sessionId, "s1");
      expect(c.partNumber, 3);
      expect(c.etag, "etag-3");
    });

    test("parses partFailed with optional httpStatus", () {
      final e =
          WindowedUploadEvent.fromMap({
                "type": "partFailed",
                "sessionId": "s1",
                "partNumber": 2,
                "errorCode": "urlExpired",
                "httpStatus": 403,
              })
              as WindowedPartFailed;
      expect(e.errorCode, "urlExpired");
      expect(e.httpStatus, 403);
    });

    test("parses needUrls part numbers", () {
      final e =
          WindowedUploadEvent.fromMap({
                "type": "needUrls",
                "sessionId": "s1",
                "partNumbers": [4, 5, 6],
              })
              as WindowedNeedUrls;
      expect(e.partNumbers, [4, 5, 6]);
    });

    test("parses progress", () {
      final e =
          WindowedUploadEvent.fromMap({
                "type": "progress",
                "sessionId": "s1",
                "bytesSent": 1024,
                "totalBytes": 4096,
              })
              as WindowedProgress;
      expect(e.bytesSent, 1024);
      expect(e.totalBytes, 4096);
    });

    test("parses sessionDrained", () {
      expect(
        WindowedUploadEvent.fromMap({
          "type": "sessionDrained",
          "sessionId": "s1",
        }),
        isA<WindowedSessionDrained>(),
      );
    });

    test("returns null for an unrecognised event", () {
      expect(
        WindowedUploadEvent.fromMap({"type": "banana", "sessionId": "s1"}),
        isNull,
      );
    });
  });

  group("manifest marshalling", () {
    test("part plan serialises url expiry as fractional epoch seconds", () {
      final plan = WindowedPartPlan(
        partNumber: 1,
        offset: 0,
        length: 100,
        url: "https://x",
        urlExpiresAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );
      expect(plan.toMap()["urlExpiresAt"], 2.0);
    });

    test("manifest includes every part", () {
      const m = WindowedSessionManifest(
        sessionId: "s1",
        fileUrl: "documents://s1.mp4",
        contentType: "video/mp4",
        fileSize: 300,
        chunkSize: 100,
        windowSize: 8,
        parts: [
          WindowedPartPlan(partNumber: 1, offset: 0, length: 100, url: "u1"),
          WindowedPartPlan(partNumber: 2, offset: 100, length: 100, url: "u2"),
        ],
      );
      expect((m.toMap()["parts"] as List).length, 2);
      expect(m.toMap()["windowSize"], 8);
    });
  });

  group("setTransferConcurrency", () {
    test("invokes the channel with maxInFlight", () async {
      const channel = MethodChannel("ios_windowed_uploader");
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = IosWindowedUploaderService();
      final err = await service.setTransferConcurrency(maxInFlight: 8);

      expect(err, isNull);
      expect(calls.single.method, "setTransferConcurrency");
      expect(calls.single.arguments, {"maxInFlight": 8});
    });
  });
}
