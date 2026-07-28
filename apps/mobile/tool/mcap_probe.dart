// Throwaway verification harness for the pure-Dart MCAP reader.
// Usage: dart run tool/mcap_probe.dart <path-to.mcap>

// ignore_for_file: avoid_print

import "package:stera/src/services/mcap_reader/cdr/ros2_message_decoder.dart";
import "package:stera/src/services/mcap_reader/mcap_reader.dart";

Future<void> main(List<String> args) async {
  final reader = await McapReader.open(args.first);
  final topics = reader.topics;
  print("topics: ${topics.length}, chunks: ${reader.chunkIndexes.length}, "
      "metadata: ${reader.metadataIndexes.map((m) => m.name).toList()}");

  for (final topic in topics) {
    final index = await reader.buildTopicIndex(topic.channel.id);
    final countsMatch = index.length == topic.messageCount ? "OK" : "MISMATCH";
    final probes = index.length < 3
        ? List.generate(index.length, (i) => i)
        : [0, index.length ~/ 2, index.length - 1];
    final summaries = <String>[];
    for (final i in probes) {
      final msg = await reader.readMessage(index[i]);
      final decoded = Ros2MessageDecoder.decode(topic.schemaName, msg.payload);
      final hasError = decoded.fields.any((f) => f.key == "decode error");
      var tag = hasError
          ? "ERR(${decoded.fields.last.value})"
          : decoded.fields.take(4).map((f) => "${f.key}=${f.value}").join(", ");
      final jpeg = decoded.jpegBytes;
      if (jpeg != null) {
        final soi = jpeg.length > 4 && jpeg[0] == 0xFF && jpeg[1] == 0xD8;
        final eoi = jpeg[jpeg.length - 2] == 0xFF && jpeg[jpeg.length - 1] == 0xD9;
        tag = "JPEG ${jpeg.length}B soi=$soi eoi=$eoi";
      }
      final depth = decoded.depth;
      if (depth != null) {
        final nonZero = depth.values.where((v) => v != 0).length;
        tag = "DEPTH ${depth.width}x${depth.height} nonzero=$nonZero";
      }
      final scene = decoded.scene;
      if (scene != null) {
        tag += " | SCENE pts=${(scene.points?.length ?? 0) ~/ 3}"
            " strip=${(scene.polyline?.length ?? 0) ~/ 3}"
            " segs=${(scene.lineSegments?.length ?? 0) ~/ 6}"
            " poses=${scene.poses.length}";
        final p = scene.points ?? scene.polyline ?? scene.lineSegments;
        if (p != null && p.length >= 3) {
          tag += " first=(${p[0].toStringAsFixed(2)},"
              "${p[1].toStringAsFixed(2)},${p[2].toStringAsFixed(2)})";
        }
      }
      summaries.add("[$i] $tag");
    }
    print("${topic.topic} (${topic.schemaName}) "
        "count=${topic.messageCount}[$countsMatch] "
        "hz=${topic.frequencyHz.toStringAsFixed(1)} "
        "dur=${topic.durationSeconds.toStringAsFixed(1)}s");
    for (final s in summaries) {
      print("    $s");
    }
  }

  if (reader.metadataIndexes.isNotEmpty) {
    final meta = await reader.readMetadata(reader.metadataIndexes.first);
    print("metadata[0] keys: ${meta.keys.toList()}");
  }
  await reader.close();
}
