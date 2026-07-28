import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/formatters/format_bytes.dart";
import "package:stera/src/core/common/widgets/app_card.dart";
import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/mcap_preview/ui/mcap_preview_page.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_error_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_loading_state.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";
import "package:stera/src/modules/recordings/ui/widgets/recording_session_tile.dart";
import "package:stera/src/services/recordings_service/data/models/recording_session.dart";

/// The on-device recordings grid: every session the recorder has written, each
/// opening into the MCAP preview. The only way into the preview in an auth-free
/// build, since there is no upload library to browse.
class CaptureRecordingsSection extends StatelessWidget {
  const CaptureRecordingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingsProvider>(
      builder: (context, provider, child) {
        return AppCard(
          // Horizontal only: the gap below is owned by the page, which puts the
          // record action there.
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            // Sized by its content: the page scrolls this alongside the demo
            // card, so the section can't claim the remaining height itself.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: "Recordings",
                number: provider.sessions.length,
                subtitle: _subtitleFor(provider),
              ),
              AppSpacing.gapMd,
              _body(context, provider),
            ],
          ),
        );
      },
    );
  }

  String _subtitleFor(RecordingsProvider provider) {
    if (provider.sessions.isEmpty) return "Stored on this device";
    final count = provider.sessions.length;
    final noun = count == 1 ? "recording" : "recordings";
    return "$count $noun • ${formatBytes(provider.totalStorageUsedBytes)}";
  }

  Widget _body(BuildContext context, RecordingsProvider provider) {
    // The empty/loading/error states are intrinsically tiny; padding keeps the
    // card from collapsing to a sliver when there is nothing to show.
    Widget state(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: child,
    );

    if (provider.isLoading && provider.sessions.isEmpty) {
      return state(const McapLoadingState(message: "Reading recordings…"));
    }

    if (provider.error != null && provider.sessions.isEmpty) {
      return state(McapErrorState(message: provider.error!));
    }

    if (provider.sessions.isEmpty) {
      return state(
        const McapErrorState(
          message:
              "No recordings yet.\nTap Start Recording to capture your first "
              "session.",
          showIcon: false,
        ),
      );
    }

    // Same grid geometry as `NotStartedVideosGridView` in the authed build, so
    // a recording reads identically whether or not it can be uploaded.
    // shrinkWrap + no physics: the page owns the scroll, so the grid lays out at
    // its natural height beneath the demo card instead of fighting it for space.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: provider.sessions.length,
      itemBuilder: (context, index) {
        final session = provider.sessions[index];
        return RecordingSessionTile(
          session: session,
          isFinalizing: provider.isFinalizing(session),
          onPreview: (item) => _openPreview(context, item),
          onDelete: (item) => _confirmDelete(context, provider, item),
        );
      },
    );
  }

  void _openPreview(BuildContext context, RecordingSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => McapPreviewPage(
          sessionDir: session.fullPath,
          title: RecordingSessionTile.titleFor(session),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RecordingsProvider provider,
    RecordingSession session,
  ) async {
    final shouldDelete = await AppConfirmationDialog.show(
      context,
      title: "Delete recording?",
      message:
          "This permanently removes the recording and its data from this "
          "device. This cannot be undone.",
      cancelText: "Cancel",
      confirmText: "Delete",
      isDestructive: true,
    );
    if (!shouldDelete) return;
    await provider.deleteSession(session.directoryName);
  }
}
