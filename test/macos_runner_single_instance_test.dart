import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS runner delegates single-instance enforcement to LaunchServices', () {
    final appDelegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final mainWindow = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('<key>LSMultipleInstancesProhibited</key>'));
    expect(infoPlist, contains('<true/>'));
    expect(appDelegate, contains('applicationShouldHandleReopen'));
    expect(appDelegate, isNot(contains('flock(')));
    expect(appDelegate, isNot(contains('primaryInstanceLock')));
    expect(appDelegate, isNot(contains('NSApp.terminate')));
    expect(mainWindow, isNot(contains('acquirePrimaryInstanceLock')));
    expect(mainWindow, isNot(contains('NSApp.terminate')));
  });
}
