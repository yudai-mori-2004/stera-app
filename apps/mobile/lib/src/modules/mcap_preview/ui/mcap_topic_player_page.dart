import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_topic_player_provider.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/player/mcap_data_player_view.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/player/mcap_visual_player_view.dart";
import "package:stera/src/services/mcap_reader/cdr/ros2_message_decoder.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";
import "package:stera/src/services/mcap_reader/mcap_reader.dart";

/// Plays one MCAP topic back on its recorded timeline. Landscape-friendly:
/// image/depth topics get a fullscreen immersive player
/// ([McapVisualPlayerView]), everything else a themed card of live decoded
/// field values ([McapDataPlayerView]).
///
/// Owns the [McapTopicPlayerProvider] and the orientation unlock; borrows
/// the [McapReader] owned by the preview page beneath it.
class McapTopicPlayerPage extends StatefulWidget {
  const McapTopicPlayerPage({
    super.key,
    required this.reader,
    required this.topic,
  });

  final McapReader reader;
  final McapTopicInfo topic;

  @override
  State<McapTopicPlayerPage> createState() => _McapTopicPlayerPageState();
}

class _McapTopicPlayerPageState extends State<McapTopicPlayerPage> {
  late final McapTopicPlayerProvider _player;

  bool get _isVisualTopic =>
      widget.topic.schemaName == Ros2MessageDecoder.compressedImageSchema ||
      widget.topic.schemaName == Ros2MessageDecoder.rawImageSchema;

  @override
  void initState() {
    super.initState();
    // The app is portrait-locked globally; playback opts into landscape and
    // dispose restores the lock (same pattern as DemoVideoFullscreenPage).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _player = McapTopicPlayerProvider(
      reader: widget.reader,
      topic: widget.topic,
    );
    _player.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode JPEG frames at display resolution — full-4K decode per frame is
    // what makes playback lag. Tracks rotation via MediaQuery changes.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _player.decodeTargetWidth = (math.max(size.width, size.height) * dpr)
        .round()
        .clamp(640, 2560);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isVisualTopic
        ? McapVisualPlayerView(player: _player, topic: widget.topic)
        : McapDataPlayerView(player: _player, topic: widget.topic);
  }
}
