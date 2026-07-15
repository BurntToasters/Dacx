import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'instance_mode_service.dart';
import 'idle_inhibit_service.dart';

/// Windows shell helpers: Jump Lists + taskbar progress.
abstract final class WindowsShellService {
  static const _channel = MethodChannel(
    InstanceModeService.windowMethodChannelName,
  );

  static const updateJumpListMethod = 'updateJumpList';
  static const setTaskbarProgressMethod = 'setTaskbarProgress';
  static const setIdleInhibitMethod = IdleInhibitService.setIdleInhibitMethod;

  /// Prevents system/display idle sleep while [inhibit] is true.
  static Future<void> setIdleInhibit(bool inhibit) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(setIdleInhibitMethod, inhibit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: setIdleInhibit failed: $e');
      }
    }
  }

  /// Pushes recent local/URL paths into the taskbar Jump List.
  static Future<void> updateJumpList(List<String> paths) async {
    if (!Platform.isWindows) return;
    final cleaned = paths
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .take(12)
        .toList(growable: false);
    try {
      await _channel.invokeMethod<bool>(updateJumpListMethod, cleaned);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: updateJumpList failed: $e');
      }
    }
  }

  /// [progress] in `0..1` while playing; pass a negative value to clear.
  static Future<void> setTaskbarProgress(double progress) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>(setTaskbarProgressMethod, progress);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: setTaskbarProgress failed: $e');
      }
    }
  }

  static Future<void> clearTaskbarProgress() => setTaskbarProgress(-1);
}
