import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/app_build_version.dart';

void main() {
  group('AppBuildVersion', () {
    test('exposes a valid compile-time SemVer in release validation', () {
      const embedded = AppBuildVersion.embeddedSemver;
      if (embedded.isEmpty) return;

      expect(
        AppBuildVersion.resolve(
          platformVersion: '3.0.0.2',
          buildNumber: '38',
        ),
        embedded,
      );
    });

    test('prefers the embedded pubspec SemVer over macOS bundle metadata', () {
      expect(
        AppBuildVersion.resolve(
          platformVersion: '3.0.0.2',
          buildNumber: '38',
          embeddedVersion: '3.0.0-picmanager.2+38',
        ),
        '3.0.0-picmanager.2+38',
      );
    });

    test('recombines PackageInfo version and build number as a fallback', () {
      expect(
        AppBuildVersion.resolve(
          platformVersion: '3.0.0',
          buildNumber: '36',
          embeddedVersion: '',
        ),
        '3.0.0+36',
      );
    });

    test('rejects an invalid embedded version instead of hiding a bad build', () {
      expect(
        () => AppBuildVersion.resolve(
          platformVersion: '3.0.0.2',
          buildNumber: '38',
          embeddedVersion: '3.0.0.2',
        ),
        throwsFormatException,
      );
    });
  });
}
