import "dart:io";

import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/ar_recorder/ui/ar_recorder_page.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_unsupported_device_bottom_sheet.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/permission_service/permission_service.dart";
import "package:stera_recorder/stera_recorder.dart";

/// The one way to open the AR recorder.
///
/// Owns the pre-flight the recorder itself does not do: AR availability on
/// Android, and *requesting* camera permission — `ArRecorderProvider
/// .initializeSession` only ever **checks** it, so a caller that skips this
/// leaves the recorder sitting permission-denied with no way out.
///
/// Deliberately knows nothing about uploads, auth or the DB: it resolves to a
/// session directory on disk and the caller decides what that means. The upload
/// flow turns it into an `Upload` row; the auth-free capture shell just refreshes
/// its list.
abstract final class ArRecorderLauncher {
  /// Pushes the recorder and returns `(sessionDir, null)` on success.
  ///
  /// On failure the directory is null and the [Failure] says why, following the
  /// app's `(value, Failure?)` convention. The one case that returns
  /// `(null, null)` is an unsupported Android device: the explanatory sheet has
  /// already been shown, so a toast on top of it would just be noise.
  ///
  /// [checkArSupport] is false only for the upload flow, which runs its own
  /// availability check earlier in the sequence (before a couple of network
  /// calls); running it again here would show that sheet twice on one tap.
  static Future<(String?, Failure?)> launch(
    BuildContext? context, {
    bool checkArSupport = true,
  }) async {
    var ctx = context ?? AppRouter.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      return (
        null,
        Failure(code: ErrorType.unknown, message: "Context not mounted"),
      );
    }

    if (checkArSupport && Platform.isAndroid) {
      final isArSupported = await ArRecorderService.checkArAvailability();
      if (!isArSupported) {
        if (!ctx.mounted) return (null, null);
        await showModalBottomSheet(
          context: ctx,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => const ArUnsupportedDeviceBottomSheet(),
        );
        return (null, null);
      }
    }

    final hasCamera = await PermissionService.ensureCameraPermission();
    if (!hasCamera) {
      return (
        null,
        Failure(code: ErrorType.unknown, message: "Missing camera permission"),
      );
    }

    // The permission prompt can outlive the context passed in, so re-resolve
    // against the live navigator before pushing.
    ctx = AppRouter.navigatorKey.currentContext ?? ctx;
    if (!ctx.mounted) {
      return (
        null,
        Failure(code: ErrorType.unknown, message: "Context not mounted"),
      );
    }

    final sessionDir = await Navigator.of(ctx).push<String>(
      CupertinoPageRoute(
        settings: const RouteSettings(name: ArRecorderPage.routeName),
        builder: (_) => const ArRecorderPage(),
      ),
    );

    if (sessionDir == null) {
      return (
        null,
        Failure(
          code: ErrorType.cancelled,
          message: "User cancelled recording",
        ),
      );
    }

    return (sessionDir, null);
  }
}
