import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/hardware_acceleration_service.dart';

void main() {
  group('HardwareAccelerationService.shouldEnableHardwareAcceleration', () {
    test('"no" disables acceleration on every platform', () {
      expect(
        HardwareAccelerationService.shouldEnableHardwareAcceleration('no'),
        isFalse,
      );
    });

    test('"auto-safe" disables acceleration on every platform', () {
      expect(
        HardwareAccelerationService.shouldEnableHardwareAcceleration(
          'auto-safe',
        ),
        isFalse,
      );
    });

    test('Linux debug builds disable acceleration', () {
      if (!Platform.isLinux) return;
      expect(
        HardwareAccelerationService.shouldEnableHardwareAcceleration('auto'),
        isFalse,
      );
    });
  });

  group('HardwareAccelerationService.debugStatusReason', () {
    test('explains "no"', () {
      expect(
        HardwareAccelerationService.debugStatusReason('no'),
        'Disabled by setting: Off',
      );
    });

    test('explains "auto-safe"', () {
      expect(
        HardwareAccelerationService.debugStatusReason('auto-safe'),
        'Disabled by setting: Safe',
      );
    });

    test('reports Linux debug-build reason on Linux', () {
      if (!Platform.isLinux) return;
      expect(
        HardwareAccelerationService.debugStatusReason('auto'),
        'Disabled in Linux debug builds',
      );
    });

    test('returns non-empty reason for any value', () {
      expect(HardwareAccelerationService.debugStatusReason('auto'), isNotEmpty);
      expect(
        HardwareAccelerationService.debugStatusReason('vaapi'),
        isNotEmpty,
      );
    });
  });
}
