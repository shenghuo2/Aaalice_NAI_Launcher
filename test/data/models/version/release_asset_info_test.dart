import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';

void main() {
  group('ReleaseAssetInfo', () {
    test('detects Windows installer asset', () {
      final asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0-beta13+16_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
        'size': 123,
      });

      expect(asset.type, ReleaseAssetType.windowsInstaller);
      expect(asset.platform, 'windows');
      expect(asset.supportsInAppInstall, isTrue);
      expect(asset.typeId, 'windows-installer');
    });

    test('keeps x64 Windows assets architecture-specific', () {
      final installer = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_x64_3.0.0+36_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
      });
      final portable = ReleaseAssetInfo.fromManifestAsset({
        'type': 'windows-x64-portable',
        'fileName': 'NAI_Launcher_Windows_x64_3.0.0+36_Portable.zip',
      });

      expect(installer.type, ReleaseAssetType.windowsX64Installer);
      expect(installer.platform, 'windows-x64');
      expect(installer.typeId, 'windows-x64-installer');
      expect(portable.type, ReleaseAssetType.windowsX64Portable);
      expect(portable.isWindowsPortable, isTrue);
      expect(portable.supportsInAppInstall, isTrue);
    });

    test('detects portable assets', () {
      final windowsAsset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0_Portable.zip',
        'browser_download_url': 'https://example.com/windows.zip',
      });
      final macosAsset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_macOS_1.0.0_Portable.zip',
        'browser_download_url': 'https://example.com/macos.zip',
      });

      expect(windowsAsset.type, ReleaseAssetType.windowsPortable);
      expect(windowsAsset.supportsInAppInstall, isTrue);
      expect(macosAsset.type, ReleaseAssetType.macosPortable);
      expect(macosAsset.supportsInAppInstall, isFalse);
      expect(macosAsset.platform, 'macos');
    });

    test('keeps split macOS assets architecture-specific', () {
      final arm64Asset = ReleaseAssetInfo.fromManifestAsset({
        'type': 'macos-arm64-portable',
        'fileName': 'NAI_Launcher_macOS_arm64_3.0.0_Portable.zip',
      });
      final x64Asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_macOS_x64_3.0.0_Portable.zip',
        'browser_download_url': 'https://example.com/macos-x64.zip',
      });

      expect(arm64Asset.type, ReleaseAssetType.macosArm64Portable);
      expect(arm64Asset.typeId, 'macos-arm64-portable');
      expect(x64Asset.type, ReleaseAssetType.macosX64Portable);
      expect(x64Asset.platform, 'macos-x64');
    });

    test('detects split macOS DMGs as in-app installable updates', () {
      final arm64 = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_macOS_arm64_3.1.0+38.dmg',
        'browser_download_url': 'https://example.com/macos-arm64.dmg',
      });
      final x64 = ReleaseAssetInfo.fromManifestAsset({
        'type': 'macos-x64-dmg',
        'fileName': 'NAI_Launcher_macOS_x64_3.1.0+38.dmg',
      });

      expect(arm64.type, ReleaseAssetType.macosArm64Dmg);
      expect(arm64.typeId, 'macos-arm64-dmg');
      expect(arm64.isMacOSDmg, isTrue);
      expect(arm64.supportsInAppInstall, isTrue);
      expect(x64.type, ReleaseAssetType.macosX64Dmg);
      expect(x64.platform, 'macos-x64');
      expect(x64.supportsInAppInstall, isTrue);
    });

    test('detects Android APK as a verified system-installed update', () {
      final asset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Android_1.0.0+17.apk',
        'browser_download_url': 'https://example.com/launcher.apk',
        'size': 456,
      });

      expect(asset.type, ReleaseAssetType.androidApk);
      expect(asset.platform, 'android');
      expect(asset.supportsInAppInstall, isTrue);
      expect(asset.typeId, 'android-apk');
      expect(asset.label, 'Android APK');
    });

    test('keeps split Android APKs ABI-specific', () {
      final arm64 = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Android_arm64-v8a_3.0.0+36.apk',
        'browser_download_url': 'https://example.com/arm64.apk',
      });
      final armv7 = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Android_armeabi-v7a_3.0.0+36.apk',
        'browser_download_url': 'https://example.com/armv7.apk',
      });
      final x64 = ReleaseAssetInfo.fromManifestAsset({
        'type': 'android-x86_64-apk',
        'fileName': 'NAI_Launcher_Android_x86_64_3.0.0+36.apk',
      });

      expect(arm64.type, ReleaseAssetType.androidArm64V8aApk);
      expect(arm64.platform, 'android-arm64-v8a');
      expect(armv7.type, ReleaseAssetType.androidArmeabiV7aApk);
      expect(x64.type, ReleaseAssetType.androidX8664Apk);
      expect(x64.typeId, 'android-x86_64-apk');
      expect([arm64, armv7, x64].every((asset) => asset.isAndroidApk), isTrue);
    });

    test('merges manifest metadata with GitHub asset', () {
      final githubAsset = ReleaseAssetInfo.fromGitHubAsset({
        'name': 'NAI_Launcher_Windows_1.0.0_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
        'size': 123,
      });
      final asset = ReleaseAssetInfo.fromManifestAsset({
        'type': 'windows-installer',
        'fileName': 'NAI_Launcher_Windows_1.0.0_Setup.exe',
        'sha256': 'abc123',
        'description': '安装版',
      }, githubAsset: githubAsset);

      expect(asset.downloadUrl, githubAsset.downloadUrl);
      expect(asset.size, 123);
      expect(asset.sha256, 'abc123');
      expect(asset.description, '安装版');
    });
  });
}
