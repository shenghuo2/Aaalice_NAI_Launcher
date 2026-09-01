import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS runner tolerates an inherited updater lock', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('NAI_LAUNCHER_UPDATE_RESTART'));
    expect(source, contains('pending_update.json'));
    expect(source, contains('updateLockWaitSeconds'));
    expect(source, contains('usleep(250_000)'));
    expect(source, contains('FD_CLOEXEC'));
  });
}
