import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/instance_mode_service.dart';

void main() {
  group('InstanceModeService', () {
    setUp(() async {
      await InstanceModeService.setAllowMultipleInstances(false);
    });

    tearDown(() async {
      await InstanceModeService.setAllowMultipleInstances(false);
    });

    test('flag file is absent by default', () {
      expect(InstanceModeService.isAllowMultipleInstancesEnabled(), isFalse);
    });

    test('toggling on creates the flag file; toggling off removes it',
        () async {
      await InstanceModeService.setAllowMultipleInstances(true);
      expect(InstanceModeService.isAllowMultipleInstancesEnabled(), isTrue);
      expect(File(InstanceModeService.flagFilePath()).existsSync(), isTrue);

      await InstanceModeService.setAllowMultipleInstances(false);
      expect(InstanceModeService.isAllowMultipleInstancesEnabled(), isFalse);
      expect(File(InstanceModeService.flagFilePath()).existsSync(), isFalse);
    });

    test('setAllowMultipleInstances(true) is idempotent', () async {
      await InstanceModeService.setAllowMultipleInstances(true);
      await InstanceModeService.setAllowMultipleInstances(true);
      expect(InstanceModeService.isAllowMultipleInstancesEnabled(), isTrue);
    });

    test('setAllowMultipleInstances(false) when already off is a no-op',
        () async {
      await InstanceModeService.setAllowMultipleInstances(false);
      expect(InstanceModeService.isAllowMultipleInstancesEnabled(), isFalse);
    });

    test('newInstanceFlag is the documented flag string', () {
      expect(InstanceModeService.newInstanceFlag, '--new-instance');
    });
  });
}
