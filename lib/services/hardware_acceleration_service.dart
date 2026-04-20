import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class HardwareAccelerationService {
  static bool? _macHardwareAccelerationSupportedCache;
  static bool _macHardwareAccelerationSupportLogged = false;

  static bool shouldEnableHardwareAcceleration(String hwDec) {
    if (hwDec == 'no' || hwDec == 'auto-safe') return false;
    if (Platform.isMacOS && !supportsMacHardwareAcceleration()) return false;
    if (Platform.isLinux && kDebugMode) return false;
    return true;
  }

  static String debugStatusReason(String hwDec) {
    if (hwDec == 'no') return 'Disabled by setting: Off';
    if (hwDec == 'auto-safe') return 'Disabled by setting: Safe';
    if (Platform.isMacOS && !supportsMacHardwareAcceleration()) {
      return 'Disabled: unsupported macOS GPU/virtualized environment';
    }
    if (Platform.isLinux && kDebugMode) {
      return 'Disabled in Linux debug builds';
    }
    return 'Enabled by current configuration';
  }

  static bool supportsMacHardwareAcceleration() {
    if (!Platform.isMacOS) return true;
    final cached = _macHardwareAccelerationSupportedCache;
    if (cached != null) return cached;

    var supported = true;

    try {
      final modelResult = Process.runSync('sysctl', ['-n', 'hw.model']);
      if (modelResult.exitCode == 0) {
        final model = modelResult.stdout.toString().trim().toLowerCase();
        if (model.contains('virtual') ||
            model.contains('vmware') ||
            model.contains('qemu') ||
            model.contains('parallels')) {
          supported = false;
        }
      }
    } catch (_) {}

    if (supported) {
      try {
        final profilerResult = Process.runSync('/usr/sbin/system_profiler', [
          'SPDisplaysDataType',
          '-json',
          '-detailLevel',
          'mini',
        ]);

        if (profilerResult.exitCode == 0) {
          final json =
              jsonDecode(profilerResult.stdout.toString())
                  as Map<String, dynamic>;
          final displays = (json['SPDisplaysDataType'] as List?) ?? const [];
          if (displays.isEmpty) {
            supported = false;
          } else {
            final anyMetalSupport = displays.any((entry) {
              if (entry is! Map) return false;
              for (final value in entry.values) {
                final s = value?.toString().toLowerCase() ?? '';
                if (s.contains('metal') &&
                    (s.contains('supported') ||
                        s.contains('available') ||
                        s.contains('yes'))) {
                  return true;
                }
              }
              return false;
            });
            if (!anyMetalSupport) {
              supported = false;
            }
          }
        }
      } catch (_) {}
    }

    _macHardwareAccelerationSupportedCache = supported;
    if (!_macHardwareAccelerationSupportLogged) {
      _macHardwareAccelerationSupportLogged = true;
      debugPrint(
        'macOS HW acceleration support detected: ${supported ? 'available' : 'not available'}',
      );
    }
    return supported;
  }
}
