import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_topic_player_provider.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_card.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_error_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_preview_header.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/player/mcap_data_controls.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/scene3d_view.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";

/// Themed card player for non-image topics: live decoded field values, a 3D
/// scene when the topic carries geometry, and fixed transport controls.
/// Owns only the 3D/raw-fields toggle; playback state lives in the borrowed
/// [McapTopicPlayerProvider].
class McapDataPlayerView extends StatefulWidget {
  final McapTopicPlayerProvider player;
  final McapTopicInfo topic;

  const McapDataPlayerView({
    super.key,
    required this.player,
    required this.topic,
  });

  @override
  State<McapDataPlayerView> createState() => _McapDataPlayerViewState();
}

class _McapDataPlayerViewState extends State<McapDataPlayerView> {
  /// For geometry topics: show the raw decoded fields instead of the 3D view.
  bool _showRawFields = false;

  McapTopicPlayerProvider get _player => widget.player;

  bool get _hasScene {
    final scene = _player.current?.scene;
    return scene != null && !scene.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic.topic;
    final splitAt = topic.lastIndexOf("/");
    final text1 = splitAt <= 0 ? "" : topic.substring(0, splitAt + 1);
    final text2 = splitAt < 0 ? topic : topic.substring(splitAt + 1);

    return Scaffold(
      body: Container(
        width: context.w,
        height: context.h,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              context.colors.surfacePrimary,
              BlendMode.modulate,
            ),
          ),
        ),
        child: SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: McapPreviewHeader(
              text1: text1,
              text2: text2,
              fontSize: AppType.xl2,
              actions: [
                // The 3D/fields toggle appears once the first geometry frame
                // decodes.
                ListenableBuilder(
                  listenable: _player,
                  builder: (context, _) {
                    if (!_hasScene) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: IconButton(
                        tooltip: _showRawFields ? "3D view" : "Raw fields",
                        icon: Icon(
                          _showRawFields
                              ? Icons.view_in_ar_outlined
                              : Icons.list_alt_outlined,
                          color: context.colors.textPrimary,
                        ),
                        onPressed: () =>
                            setState(() => _showRawFields = !_showRawFields),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: ListenableBuilder(
              listenable: _player,
              builder: (context, _) {
                if (_player.isLoading) {
                  return Center(
                    child: CupertinoActivityIndicator(
                      color: context.colors.textPrimary,
                    ),
                  );
                }
                final error = _player.error;
                if (error != null && _player.current == null) {
                  return McapErrorState(message: error, showIcon: false);
                }
                return Column(
                  children: [
                    Expanded(
                      child: _hasScene && !_showRawFields
                          ? _SceneCard(player: _player)
                          : _FieldsCard(
                              fields: _player.current?.fields ?? const [],
                            ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    McapDataControls(player: _player),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  final McapTopicPlayerProvider player;

  const _SceneCard({required this.player});

  @override
  Widget build(BuildContext context) {
    return McapCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Scene3DView(
          scene: player.current?.scene,
          trailPositions: player.trailPositions,
          trailTimesNs: player.trailTimesNs,
          playheadNs: player.playheadNs,
        ),
      ),
    );
  }
}

class _FieldsCard extends StatelessWidget {
  final List<MapEntry<String, String>> fields;

  const _FieldsCard({required this.fields});

  @override
  Widget build(BuildContext context) {
    return McapCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        itemCount: fields.length,
        separatorBuilder: (_, _) =>
            Divider(color: context.colors.borderDivider, height: 1),
        itemBuilder: (context, index) {
          final field = fields[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.key,
                  style: context.textTheme.bodyXsMedium.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  field.value,
                  style: context.textTheme.bodySmMono.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
