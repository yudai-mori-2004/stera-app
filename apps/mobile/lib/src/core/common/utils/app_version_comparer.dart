import "package:pub_semver/pub_semver.dart";

class AppVersionComparer {
  static bool isMajorUpdate({String? currentVersion, String? minVersion}) {
    if (currentVersion == null || minVersion == null) {
      return false;
    }

    try {
      final current = Version.parse(currentVersion);
      final minimum = Version.parse(minVersion);
      final isUpdateNeeded = current < minimum;

      return isUpdateNeeded;
    } catch (e) {
      return true;
    }
  }
}
