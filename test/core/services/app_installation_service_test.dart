import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/app_installation_service.dart';

void main() {
  group('AppInstallationService', () {
    test('detects executable inside install directory', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher\nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher',
        ),
        isTrue,
      );
    });

    test('does not match similar path prefixes', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Portable\nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher',
        ),
        isFalse,
      );
    });

    test('normalizes slash and trailing separator differences', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              'C:/Users/alice/AppData/Local/Programs/Aaalice NAI Launcher/nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher\',
        ),
        isTrue,
      );
    });

    test('selects the matching split macOS release architecture', () {
      expect(
        AppInstallationService.macosReleaseAssetPreference(Abi.macosArm64),
        'macos-arm64',
      );
      expect(
        AppInstallationService.macosReleaseAssetPreference(Abi.macosX64),
        'macos-x64',
      );
      expect(
        AppInstallationService.macosReleaseAssetPreference(Abi.linuxX64),
        'macos',
      );
    });

    test('finds a macOS app bundle from its executable', () {
      expect(
        AppInstallationService.macosAppBundleFromExecutable(
          '/Applications/Aaalice NAI Launcher.app/Contents/MacOS/nai_launcher',
        ),
        '/Applications/Aaalice NAI Launcher.app',
      );
      expect(
        AppInstallationService.macosAppBundleFromExecutable('/usr/bin/dart'),
        isNull,
      );
    });

    test('rejects read-only and translocated macOS app bundles', () {
      expect(
        AppInstallationService.isMacOSBundleReplaceable(
          '/Applications/Aaalice NAI Launcher.app',
        ),
        isTrue,
      );
      expect(
        AppInstallationService.isMacOSBundleReplaceable(
          '/Volumes/NAI Launcher/Aaalice NAI Launcher.app',
        ),
        isFalse,
      );
      expect(
        AppInstallationService.isMacOSBundleReplaceable(
          '/private/var/folders/AppTranslocation/ABC/App.app',
        ),
        isFalse,
      );
    });

    test('selects architecture-specific Windows x64 packages', () {
      expect(
        AppInstallationService.windowsReleaseAssetPreference(
          installed: true,
          abi: Abi.windowsX64,
        ),
        'windows-x64-installer',
      );
      expect(
        AppInstallationService.windowsReleaseAssetPreference(
          installed: false,
          abi: Abi.windowsX64,
        ),
        'windows-x64-portable',
      );
      expect(
        AppInstallationService.windowsReleaseAssetPreference(
          installed: true,
          abi: Abi.windowsArm64,
        ),
        'windows-installer',
      );
    });

    test('selects the matching split Android release ABI', () {
      expect(
        AppInstallationService.androidReleaseAssetPreference(Abi.androidArm64),
        'android-arm64-v8a',
      );
      expect(
        AppInstallationService.androidReleaseAssetPreference(Abi.androidArm),
        'android-armeabi-v7a',
      );
      expect(
        AppInstallationService.androidReleaseAssetPreference(Abi.androidX64),
        'android-x86_64',
      );
      expect(
        AppInstallationService.androidReleaseAssetPreference(Abi.androidIA32),
        'android-apk',
      );
    });
  });
}
