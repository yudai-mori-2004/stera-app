import "dart:developer" as dev;

import "package:flutter/widgets.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";

/// Header overflow action on AddUploadPage that scans
/// `<Documents>/ar_sessions/` for recordings saved on disk but missing from
/// the uploads table, and inserts them as not-started uploads.
///
/// Safety net for the flows where the finalize event can be
/// missed (leader waiting on the follower's STOPPED ack, app backgrounded
/// mid-finalize, …) leaving a take saved-but-untracked. Session dirs live in
/// the app's own Documents container (`documents://` scheme), so the upload
/// service treats recovered rows exactly like freshly recorded ones — no
/// security-scoped URL handling is involved.
class RecoverRecordingsAction {
  RecoverRecordingsAction._();

  static bool _busy = false;

  static Future<void> run(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      final recovered = await context
          .read<UploadProvider>()
          .picker
          .recoverOrphanedSessions();
      if (recovered.isEmpty) {
        AppToast.info(
          title: "No missing recordings",
          description: "Every saved recording is already in your list.",
          holdDuration: 4,
        );
      } else {
        AppToast.success(
          title:
              "Recovered ${recovered.length} recording${recovered.length == 1 ? "" : "s"}",
          description: "Added to your uploads list below.",
          holdDuration: 4,
        );
      }
    } catch (e) {
      dev.log("RecoverRecordingsAction: recovery failed - $e");
      AppToast.error(
        title: "Recovery failed",
        description: "Could not scan for saved recordings. Try again.",
        holdDuration: 4,
      );
    } finally {
      _busy = false;
    }
  }
}
