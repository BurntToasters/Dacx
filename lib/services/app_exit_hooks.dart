import 'dart:async';

import 'package:flutter/foundation.dart';

/// Work that must finish before the process ends. Window close and tray Quit
/// end the app with `windowManager.destroy()`, and macOS Cmd+Q terminates it;
/// none of them run widget `dispose`, so state saved there would be lost.
abstract final class AppExitHooks {
  static const Duration defaultTimeout = Duration(seconds: 2);

  static final List<Future<void> Function()> _hooks = [];

  static void add(Future<void> Function() hook) => _hooks.add(hook);

  static void remove(Future<void> Function() hook) => _hooks.remove(hook);

  /// Runs every hook. A hook that throws or exceeds [timeout] is skipped so
  /// it can never stop the app from quitting.
  static Future<void> runAll({Duration timeout = defaultTimeout}) async {
    for (final hook in List.of(_hooks)) {
      try {
        await hook().timeout(timeout);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: exit hook failed: $e');
        }
      }
    }
  }
}
