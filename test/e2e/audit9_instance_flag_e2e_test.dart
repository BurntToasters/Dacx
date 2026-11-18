import 'dart:io';

import 'package:dacx/services/instance_mode_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/audit9_report.dart';

const _slow = Duration(milliseconds: 120);

void main() {
  final report = Audit9Report(
    'instance-flag',
    expectedIds: [
      'M38.1',
      'M38.2',
      'M38.3',
      'M38.4',
      'M38.5',
      'M38.6',
      'M38.7',
    ],
  );

  tearDownAll(report.write);

  late Directory tempDir;
  late DebugPrintCallback originalDebugPrint;
  late List<String> logged;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('dacx_instance_flag_e2e_');
    InstanceModeService.setFlagDirForTesting(tempDir.path);
    logged = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logged.add(message);
    };
  });

  tearDown(() async {
    InstanceModeService.writeDelayHookForTesting = null;
    debugPrint = originalDebugPrint;
    InstanceModeService.setFlagDirForTesting(null);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<SettingsService> makeService({bool initial = false}) async {
    SharedPreferences.setMockInitialValues({
      if (initial) 'allow_multiple_instances': true,
    });
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  bool fileExists() => File(InstanceModeService.flagFilePath()).existsSync();

  test('M38.1 slow true then false then sync leaves no file', () async {
    final service = await makeService();
    InstanceModeService.writeDelayHookForTesting = (enabled) =>
        enabled ? Future<void>.delayed(_slow) : Future<void>.value();

    service.allowMultipleInstances = true;
    service.allowMultipleInstances = false;
    await service.syncInstanceModeFlag();
    await Future<void>.delayed(_slow * 2);

    expect(service.allowMultipleInstances, isFalse);
    expect(fileExists(), isFalse);
    report.pass('M38.1');
  });

  test('M38.2 slow false then true then sync leaves the file', () async {
    final service = await makeService(initial: true);
    await service.syncInstanceModeFlag();
    expect(fileExists(), isTrue);
    InstanceModeService.writeDelayHookForTesting = (enabled) =>
        enabled ? Future<void>.value() : Future<void>.delayed(_slow);

    service.allowMultipleInstances = false;
    service.allowMultipleInstances = true;
    await service.syncInstanceModeFlag();
    await Future<void>.delayed(_slow * 2);

    expect(service.allowMultipleInstances, isTrue);
    expect(fileExists(), isTrue);
    report.pass('M38.2');
  });

  test('M38.3 many rapid toggles end matching the last value', () async {
    for (final finalValue in [true, false]) {
      final service = await makeService();
      var call = 0;
      InstanceModeService.writeDelayHookForTesting = (enabled) {
        call++;
        return Future<void>.delayed(Duration(milliseconds: (call * 37) % 90));
      };

      for (var i = 0; i < 20; i++) {
        service.allowMultipleInstances = i.isEven;
      }
      service.allowMultipleInstances = finalValue;
      await service.syncInstanceModeFlag();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(service.allowMultipleInstances, finalValue);
      expect(fileExists(), finalValue);
    }
    report.pass('M38.3');
  });

  test('M38.4 deleting a missing file succeeds and logs nothing', () async {
    expect(fileExists(), isFalse);

    final ok = await InstanceModeService.setAllowMultipleInstances(false);

    expect(ok, isTrue);
    expect(logged, isEmpty);
    expect(fileExists(), isFalse);
    report.pass('M38.4');
  });

  test('M38.5 concurrent deletes both succeed and log nothing', () async {
    expect(await InstanceModeService.setAllowMultipleInstances(true), isTrue);
    expect(fileExists(), isTrue);

    final results = await Future.wait([
      InstanceModeService.setAllowMultipleInstances(false),
      InstanceModeService.setAllowMultipleInstances(false),
      InstanceModeService.setAllowMultipleInstances(false),
    ]);

    expect(results, everyElement(isTrue));
    expect(logged, isEmpty);
    expect(fileExists(), isFalse);
    report.pass('M38.5');
  });

  test(
    'M38.6 resetAll while a slow true is in flight leaves no file',
    () async {
      final service = await makeService();
      InstanceModeService.writeDelayHookForTesting = (enabled) =>
          enabled ? Future<void>.delayed(_slow) : Future<void>.value();

      service.allowMultipleInstances = true;
      await service.resetAll();
      await Future<void>.delayed(_slow * 2);

      expect(service.allowMultipleInstances, isFalse);
      expect(fileExists(), isFalse);
      report.pass('M38.6');
    },
  );

  test('M38.7 sync completes only after earlier writes settle', () async {
    final service = await makeService();
    InstanceModeService.writeDelayHookForTesting = (enabled) =>
        enabled ? Future<void>.value() : Future<void>.delayed(_slow);

    service.allowMultipleInstances = true;
    service.allowMultipleInstances = false;
    service.allowMultipleInstances = true;
    await service.syncInstanceModeFlag();
    expect(fileExists(), isTrue);

    await Future<void>.delayed(_slow * 2);
    expect(fileExists(), isTrue);
    expect(service.allowMultipleInstances, isTrue);
    report.pass('M38.7');
  });
}
