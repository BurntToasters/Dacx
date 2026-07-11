import 'dart:io';

import 'package:flutter/foundation.dart';

import '../playback/linux_install_kind.dart';

/// Prevents screensaver / idle sleep while media is playing (Linux).
///
/// Uses `org.freedesktop.ScreenSaver.Inhibit` via `dbus-send`. No-op on
/// non-Linux and when D-Bus is unavailable.
class IdleInhibitService {
  int? _cookie;
  bool _active = false;

  bool get isInhibited => _active && _cookie != null;

  /// Basename of the installed `.desktop` file (without extension) for MPRIS.
  static String mprisDesktopEntry() {
    if (!Platform.isLinux) return 'dacx';
    return LinuxInstallDetector.isFlatpak ? 'run.rosie.dacx' : 'dacx';
  }

  Future<void> setPlaying(bool playing) async {
    if (!Platform.isLinux) return;
    if (playing) {
      await _inhibit();
    } else {
      await _uninhibit();
    }
  }

  Future<void> _inhibit() async {
    if (_active) return;
    try {
      final result = await Process.run('dbus-send', [
        '--session',
        '--dest=org.freedesktop.ScreenSaver',
        '--type=method_call',
        '--print-reply',
        '/org/freedesktop/ScreenSaver',
        'org.freedesktop.ScreenSaver.Inhibit',
        'string:Dacx',
        'string:Playing media',
      ]);
      if (result.exitCode != 0) {
        if (kDebugMode) {
          debugPrint('Dacx: idle inhibit failed: ${result.stderr}');
        }
        return;
      }
      final cookie = parseUint32ReplyForTest('${result.stdout}');
      if (cookie == null) return;
      _cookie = cookie;
      _active = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: idle inhibit unavailable: $e');
      }
    }
  }

  Future<void> _uninhibit() async {
    final cookie = _cookie;
    _cookie = null;
    _active = false;
    if (cookie == null) return;
    try {
      await Process.run('dbus-send', [
        '--session',
        '--dest=org.freedesktop.ScreenSaver',
        '--type=method_call',
        '/org/freedesktop/ScreenSaver',
        'org.freedesktop.ScreenSaver.UnInhibit',
        'uint32:$cookie',
      ]);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: idle uninhibit failed: $e');
      }
    }
  }

  Future<void> dispose() => _uninhibit();

  /// Parses `uint32 N` from dbus-send `--print-reply` stdout.
  @visibleForTesting
  static int? parseUint32ReplyForTest(String stdout) {
    final match = RegExp(r'uint32\s+(\d+)').firstMatch(stdout);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
