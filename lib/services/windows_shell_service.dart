import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'instance_mode_service.dart';

/// Windows shell helpers: Jump Lists + taskbar progress.
abstract final class WindowsShellService {
  static const _channel = MethodChannel(
    InstanceModeService.windowMethodChannelName,
  );

  static const updateJumpListMethod = 'updateJumpList';
  static const setTaskbarProgressMethod = 'setTaskbarProgress';

  static List<String> filterJumpListPaths(List<String> paths) {
    final out = <String>[];
    for (final raw in paths) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('\\\\')) continue;
      final uri = Uri.tryParse(trimmed);
      if (uri != null &&
          uri.hasScheme &&
          !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
        continue;
      }
      out.add(trimmed);
      if (out.length >= 12) break;
    }
    return out;
  }

  /// Pushes recent local paths into the taskbar Jump List. Stream URLs are
  /// never included so private query tokens stay out of the OS shell.
  static Future<void> updateJumpList(List<String> paths) async {
    if (!Platform.isWindows) return;
    final cleaned = filterJumpListPaths(paths);
    if (cleaned.isEmpty) {
      try {
        await _channel.invokeMethod<bool>(updateJumpListMethod, const []);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: updateJumpList failed: $e');
        }
      }
      return;
    }
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
