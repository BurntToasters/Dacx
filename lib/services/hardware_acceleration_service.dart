import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum _MacMetalSupport { supported, unsupported, unknown }

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

    if (_looksLikeVirtualizedMac()) {
      supported = false;
    }

    if (supported) {
      final metalSupport = _detectMacMetalSupport();
      if (metalSupport == _MacMetalSupport.unsupported) {
        supported = false;
      }
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

  static bool _looksLikeVirtualizedMac() {
    final model = _runSyncTrimmed('sysctl', ['-n', 'hw.model']);
    if (_containsVmMarker(model)) return true;

    final hvVmmPresent = _runSyncTrimmed('sysctl', [
      '-n',
      'kern.hv_vmm_present',
    ]);
    if (hvVmmPresent == '1') return true;

    final cpuFeatures = _runSyncTrimmed('sysctl', [
      '-n',
      'machdep.cpu.features',
    ]);
    if (cpuFeatures != null &&
        RegExp(r'\bvmm\b', caseSensitive: false).hasMatch(cpuFeatures)) {
      return true;
    }

    return false;
  }

  static bool _containsVmMarker(String? value) {
    if (value == null) return false;
    final lower = value.toLowerCase();
    return lower.contains('virtual') ||
        lower.contains('vmware') ||
        lower.contains('qemu') ||
        lower.contains('parallels') ||
        lower.contains('virtualbox') ||
        lower.contains('xen');
  }

  static _MacMetalSupport _detectMacMetalSupport() {
    final output = _runSyncTrimmed('/usr/sbin/system_profiler', [
      'SPDisplaysDataType',
      '-json',
      '-detailLevel',
      'mini',
    ]);
    if (output == null || output.isEmpty) return _MacMetalSupport.unknown;

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) return _MacMetalSupport.unknown;
      final displays = decoded['SPDisplaysDataType'];
      if (displays is! List || displays.isEmpty) {
        return _MacMetalSupport.unknown;
      }

      var sawMetalSignal = false;
      var explicitMetalUnsupported = false;

      for (final entry in displays) {
        _visitLeafPairs(entry, (key, value) {
          final keyLower = key.toLowerCase();
          final valueLower = value.toLowerCase();
          final hasMetalSignal =
              keyLower.contains('metal') || valueLower.contains('metal');
          if (!hasMetalSignal) return;

          sawMetalSignal = true;
          if (_isExplicitMetalUnsupported(valueLower)) {
            explicitMetalUnsupported = true;
          }
        });
      }

      if (explicitMetalUnsupported) return _MacMetalSupport.unsupported;
      if (sawMetalSignal) return _MacMetalSupport.supported;
    } catch (_) {}

    return _MacMetalSupport.unknown;
  }

  static bool _isExplicitMetalUnsupported(String value) {
    return value.contains('spdisplays_unsupported') ||
        value.contains('not supported') ||
        value.contains('unsupported') ||
        value.contains('unavailable') ||
        value.contains('disabled');
  }

  static void _visitLeafPairs(
    Object? node,
    void Function(String key, String value) visitor,
  ) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map || value is List) {
          _visitLeafPairs(value, visitor);
        } else {
          visitor(key, value?.toString() ?? '');
        }
      }
      return;
    }
    if (node is List) {
      for (final item in node) {
        _visitLeafPairs(item, visitor);
      }
    }
  }

  static String? _runSyncTrimmed(String executable, List<String> args) {
    try {
      final result = Process.runSync(executable, args);
      if (result.exitCode != 0) return null;
      final text = result.stdout.toString().trim();
      if (text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
