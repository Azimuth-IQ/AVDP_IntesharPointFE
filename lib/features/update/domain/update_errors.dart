/// Thrown when the OS "install unknown apps" permission is not granted. The
/// caller routes the user to the system setting, then they retry the update.
class InstallPermissionDenied implements Exception {
  const InstallPermissionDenied();
  @override
  String toString() => 'Install permission not granted';
}
