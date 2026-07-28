import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_preview_provider.dart";
import "package:stera/src/modules/mcap_preview/ui/mcap_topic_player_page.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_error_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_loading_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_metadata_sheet.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_preview_content.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_preview_header.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";

/// Lists the topics (and metadata records) inside a recording's MCAP file.
/// Tapping a topic opens a playable viewer for it.
///
/// Pushed with a raw `Navigator` from the recordings list / upload tiles
/// (like `ProcessingPage`); registered in `AppRoutes` so the route name
/// resolves for observers. Requires the session directory as `extra`.
class McapPreviewPage extends StatefulWidget {
  const McapPreviewPage({super.key, this.sessionDir, this.mcapPath, this.title})
    : assert(sessionDir != null || mcapPath != null);

  static const String routeName = "/mcap-preview";

  /// Session directory to scan for the MCAP file (recordings-list entry).
  final String? sessionDir;

  /// Direct path to the MCAP file (upload-tile entry).
  final String? mcapPath;

  final String? title;

  @override
  State<McapPreviewPage> createState() => _McapPreviewPageState();
}

class _McapPreviewPageState extends State<McapPreviewPage> {
  late final McapPreviewProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = McapPreviewProvider(
      sessionDir: widget.sessionDir,
      mcapPath: widget.mcapPath,
    );
    _provider.load();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _openPlayer(McapTopicInfo topic) {
    final reader = _provider.reader;
    if (reader == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => McapTopicPlayerPage(reader: reader, topic: topic),
      ),
    );
  }

  Future<void> _showMetadata(McapMetadataIndex index) async {
    final Map<String, String> entries;
    try {
      entries = await _provider.readMetadata(index);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context: context,
        title: "Couldn't read metadata",
        description: "This recording's metadata may be incomplete.",
      );
      return;
    }
    if (!mounted) return;
    await McapMetadataSheet.show(context, title: index.name, entries: entries);
  }

  @override
  Widget build(BuildContext context) {
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
            appBar: const McapPreviewHeader(
              text1: "Recording ",
              text2: "Preview",
            ),
            body: ListenableBuilder(
              listenable: _provider,
              builder: (context, _) {
                if (_provider.isLoading) {
                  return const McapLoadingState(message: "Reading recording…");
                }
                final error = _provider.error;
                if (error != null) {
                  return McapErrorState(message: error);
                }
                if (_provider.topics.isEmpty &&
                    _provider.metadataIndexes.isEmpty) {
                  return const McapErrorState(
                    message:
                        "This recording has no readable topics.\n"
                        "It may still be finalizing — try again in a moment.",
                  );
                }
                return McapPreviewContent(
                  topics: _provider.topics,
                  metadataIndexes: _provider.metadataIndexes,
                  fileSizeBytes: _provider.fileSizeBytes,
                  title: widget.title,
                  onTopicPressed: _openPlayer,
                  onMetadataPressed: _showMetadata,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
