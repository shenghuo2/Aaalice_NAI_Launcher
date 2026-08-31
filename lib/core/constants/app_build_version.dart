import 'package:pub_semver/pub_semver.dart';

/// Resolves the canonical application version used by update checks.
///
/// Apple bundle versions only allow numeric components, so Flutter rewrites
/// prerelease versions such as `3.0.0-picmanager.2` to `3.0.0.2` on macOS.
/// Release builds embed the original pubspec version with APP_SEMVER.
class AppBuildVersion {
  AppBuildVersion._();

  static const String embeddedSemver = String.fromEnvironment('APP_SEMVER');

  static String resolve({
    required String platformVersion,
    required String buildNumber,
    String embeddedVersion = embeddedSemver,
  }) {
    final canonicalVersion = embeddedVersion.trim();
    if (canonicalVersion.isNotEmpty) {
      Version.parse(canonicalVersion);
      return canonicalVersion;
    }

    final version = platformVersion.trim();
    final build = buildNumber.trim();
    if (build.isEmpty || version.contains('+')) return version;
    return '$version+$build';
  }
}
