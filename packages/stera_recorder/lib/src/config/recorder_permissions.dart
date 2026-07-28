/// The permission checks the recorder performs before opening a session.
///
/// The host app supplies the implementation — typically a thin wrapper over
/// `permission_handler` or its own permission service — so this package doesn't
/// pull in a permissions plugin and the app keeps a single request path.
abstract class RecorderPermissions {
  /// Whether camera access is already granted. The recorder only checks — the
  /// app is responsible for requesting it.
  Future<bool> isCameraPermissionGranted();

  /// Opens the OS app settings so the user can grant a denied permission.
  Future<bool> openSettings();
}
