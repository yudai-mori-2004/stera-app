import "package:stera/src/core/common/utils/app_version_comparer.dart";
import "package:stera/src/modules/home/ui/widgets/app_update_bottomsheet.dart";
import "package:stera/src/core/config/constants/brand.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:upgrader/upgrader.dart";

class AppUpdate {
  // --- Update feed configuration -------------------------------------------
  // `bun run brand:apply` rewrites these three from packages/brand/brand.json.
  // All null - the default for a fork that has not published anywhere - means
  // in-app update checks are disabled and nothing is fetched.
  static const String? _updateFeedUrl = Brand.updateFeedUrl;
  static const String? _playStoreUrl = Brand.playStoreUrl;
  static const String? _appStoreUrl = Brand.appStoreUrl;

  static Upgrader? _upgrader;
  static bool _hasCheckedThisSession = false;
  static bool _isShowingModal = false;
  static bool _isChecking = false;

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// Where "Update now" sends the user when the feed itself does not say.
  static String? get _storeListingUrl => _isIOS ? _appStoreUrl : _playStoreUrl;

  /// Null when this build has no way to learn about a newer version.
  static Upgrader? _buildUpgrader() {
    final feed = _updateFeedUrl;
    if (feed != null) {
      return Upgrader(
        storeController: UpgraderStoreController(
          onAndroid: () => UpgraderAppcastStore(appcastURL: feed),
          oniOS: () => UpgraderAppcastStore(appcastURL: feed),
        ),
      );
    }

    // A store lookup keys off the runtime bundle id, so only run it on a
    // platform whose listing the fork has actually declared.
    return _storeListingUrl == null ? null : Upgrader();
  }

  static Future<bool> checkForUpdates(BuildContext context) async {
    if (!context.mounted) return false;
    if (_hasCheckedThisSession || _isShowingModal || _isChecking) return false;

    final upgrader = _upgrader ??= _buildUpgrader();
    if (upgrader == null) return false;

    _isChecking = true;

    try {
      await upgrader.initialize();

      final versionInfo = upgrader.versionInfo;

      // Get the actual store version (latest available version)
      final storeVersion = versionInfo?.appStoreVersion?.toString();
      final currentVersion = versionInfo?.installedVersion?.toString();
      final minVersion = versionInfo?.minAppVersion?.toString();
      final appStoreLink = versionInfo?.appStoreListingURL ?? _storeListingUrl;

      // If we can't determine store version, or have nowhere to send the user,
      // don't show the update prompt
      if (storeVersion == null ||
          currentVersion == null ||
          appStoreLink == null) {
        _hasCheckedThisSession = true;
        return false;
      }

      final shouldUpgrade = upgrader.isUpdateAvailable();
      if (!shouldUpgrade) {
        _hasCheckedThisSession = true;
        return false;
      }

      bool isMajorUpdate = AppVersionComparer.isMajorUpdate(
        currentVersion: currentVersion,
        minVersion: minVersion,
      );

      if (!context.mounted) return false;

      final description = isMajorUpdate
          ? "This version is no longer supported. Please update the app to continue uploading videos."
          : "We've added improvements to make uploads smoother and things faster behind the scenes. You can update now or continue with the current version. We recommend updating for the best experience.";

      _isShowingModal = true;
      showModalBottomSheet(
        useSafeArea: true,
        context: context,
        isDismissible: !isMajorUpdate,
        enableDrag: !isMajorUpdate,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => PopScope(
          canPop: !isMajorUpdate,
          child: AppUpdateBottomSheet(
            isMajorUpdate: isMajorUpdate,
            version: storeVersion,
            description: description,
            appStoreLink: appStoreLink,
          ),
        ),
      ).then((_) => _isShowingModal = false);

      if (!isMajorUpdate) {
        _hasCheckedThisSession = true;
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      _isChecking = false;
    }
  }
}
