import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/upload_service/utils/mcap_finalization.dart";

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("mcap_finalization");
  });

  tearDown(() => dir.delete(recursive: true));

  Future<File> write(String name, List<int> bytes) async {
    final file = File("${dir.path}/$name");
    await file.writeAsBytes(bytes);
    return file;
  }

  test("a finished mcap (trailing magic) is finalized", () async {
    final file = await write("done.mcap", [
      ...McapFinalization.magic, // leading magic
      1, 2, 3, 4, 5, // payload
      ...McapFinalization.magic, // trailing magic — finish() completed
    ]);
    expect(await McapFinalization.isFinalized(file), isTrue);
  });

  test("a still-growing mcap (no trailing magic) is not finalized", () async {
    final file = await write("growing.mcap", [
      ...McapFinalization.magic,
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, // payload, footer not yet written
    ]);
    expect(await McapFinalization.isFinalized(file), isFalse);
  });

  test("a file shorter than two magics is not finalized", () async {
    final file = await write("stub.mcap", [...McapFinalization.magic]);
    expect(await McapFinalization.isFinalized(file), isFalse);
  });

  test("a missing file is not finalized", () async {
    expect(
      await McapFinalization.isFinalized(File("${dir.path}/nope.mcap")),
      isFalse,
    );
  });
}
