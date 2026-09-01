import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/macos_update_script.dart';

void main() {
  group('MacOSUpdateScript', () {
    String buildScript({String dmgPath = '/tmp/update.dmg'}) {
      return MacOSUpdateScript.build(
        appPid: 4321,
        version: '3.0.0-picmanager.2+38',
        dmgPath: dmgPath,
        targetAppPath: '/Applications/Aaalice NAI Launcher.app',
        mountDirectory: '/tmp/nai-update/mount',
        backupAppPath: '/Applications/.Aaalice NAI Launcher.nai-backup.app',
        resultPath: '/tmp/nai-update/result.json',
        pendingMetadataPath: '/tmp/nai-update/pending.json',
        logPath: '/tmp/nai-update/update.log',
      );
    }

    test('mounts, validates, replaces, restarts and rolls back', () {
      final script = buildScript();

      expect(script, contains('AppPid=4321'));
      expect(script, contains('hdiutil attach'));
      expect(script, contains('CFBundleIdentifier'));
      expect(script, contains('CFBundleShortVersionString'));
      expect(script, contains('CFBundleVersion'));
      expect(script, contains("ExpectedVersion='3.0.0.2'"));
      expect(script, contains("ExpectedBuildVersion='38'"));
      expect(script, contains('codesign --verify --deep --strict'));
      expect(script, contains(r'mv -- "$TargetApp" "$BackupApp"'));
      expect(script, contains(r'/usr/bin/ditto "$CandidateApp" "$TargetApp"'));
      expect(script, contains(r'"$UpdatedExecutablePath" >> "$LogPath" 2>&1 &'));
      expect(script, contains(r'UpdatedExecutablePid=$!'));
      expect(
        script,
        isNot(contains(r'/usr/bin/pgrep -f -- "$UpdatedExecutablePath"')),
      );
      expect(script, contains('for iteration in {1..12}'));
      expect(script, contains(r'kill -0 "$UpdatedExecutablePid"'));
      expect(
        script,
        contains(r'/bin/kill "$UpdatedExecutablePid"'),
      );
      expect(script, contains('Previous application version restored.'));
      expect(script, contains('write_result true'));
      expect(script, contains('write_result false'));
    });

    test('publishes update results atomically after a verified restart', () {
      final script = buildScript();
      final successResult = script.lastIndexOf(
        "write_result true 'Update installed successfully.'",
      );
      final launch = script.lastIndexOf(r'launch_app "$CurrentExecutable"');

      expect(script, contains(r'ResultTemporaryPath="${ResultPath}.tmp.$$"'));
      expect(
        script,
        contains(r'mv -f -- "$ResultTemporaryPath" "$ResultPath"'),
      );
      expect(successResult, greaterThanOrEqualTo(0));
      expect(successResult, greaterThan(launch));
    });

    test('rejects execution from a mounted or translocated app', () {
      final script = buildScript();

      expect(script, contains(r'"$TargetApp" == /Volumes/*'));
      expect(script, contains(r'''"$TargetApp" == *'/AppTranslocation/'*'''));
      expect(script, contains(r'! -w "$TargetParent"'));
    });

    test('quotes shell paths containing apostrophes', () {
      final script = buildScript(dmgPath: "/tmp/alice's update.dmg");

      expect(script, contains("DmgPath='/tmp/alice'\"'\"'s update.dmg'"));
    });

    test('generated script passes the Bash parser', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'macos_update_script_',
      );
      try {
        final scriptFile = File('${tempDir.path}/update.sh');
        await scriptFile.writeAsString(buildScript());
        final result = await Process.run('/bin/bash', ['-n', scriptFile.path]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
