import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../playback/linux_install_kind.dart';
import 'instance_mode_service.dart';

/// Prevents screensaver / idle sleep while media is playing.
///
/// - Linux: `org.freedesktop.ScreenSaver.Inhibit` over a **persistent**
///   session D-Bus connection (one-shot `dbus-send` drops inhibit on exit)
/// - Windows / macOS: `setIdleInhibit` on the window method channel
class IdleInhibitService {
  static const setIdleInhibitMethod = 'setIdleInhibit';

  static const _channel = MethodChannel(
    InstanceModeService.windowMethodChannelName,
  );

  static const _screensaverName = 'org.freedesktop.ScreenSaver';
  static final _screensaverPath = DBusObjectPath(
    '/org/freedesktop/ScreenSaver',
  );

  int? _cookie;
  bool _active = false;
  DBusClient? _linuxClient;
  DBusRemoteObject? _linuxScreensaver;

  /// Optional overrides for unit tests (Linux path only).
  @visibleForTesting
  DBusClient? linuxClientForTesting;
  @visibleForTesting
  Future<DBusMethodSuccessResponse> Function(
    String interface,
    String method,
    List<DBusValue> values, {
    DBusSignature? replySignature,
  })?
  linuxCallMethodForTesting;

  bool get isInhibited => _active;

  /// Basename of the installed `.desktop` file (without extension) for MPRIS.
  static String mprisDesktopEntry() {
    if (!Platform.isLinux) return 'dacx';
    return LinuxInstallDetector.isFlatpak ? 'run.rosie.dacx' : 'dacx';
  }

  Future<void> setPlaying(bool playing) async {
    if (Platform.isLinux) {
      if (playing) {
        await _inhibitLinux();
      } else {
        await _uninhibitLinux();
      }
      return;
    }
    if (Platform.isWindows || Platform.isMacOS) {
      await _setNativeInhibit(playing);
    }
  }

  Future<void> _setNativeInhibit(bool inhibit) async {
    if (_active == inhibit) return;
    try {
      await _channel.invokeMethod<bool>(setIdleInhibitMethod, inhibit);
      _active = inhibit;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: idle inhibit unavailable: $e');
      }
    }
  }

  Future<void> _ensureLinuxClient() async {
    if (_linuxScreensaver != null) return;
    final client = linuxClientForTesting ?? DBusClient.session();
    _linuxClient = client;
    _linuxScreensaver = DBusRemoteObject(
      client,
      name: _screensaverName,
      path: _screensaverPath,
    );
  }

  Future<DBusMethodSuccessResponse> _linuxCall(
    String method,
    List<DBusValue> values, {
    DBusSignature? replySignature,
  }) async {
    final override = linuxCallMethodForTesting;
    if (override != null) {
      return override(
        _screensaverName,
        method,
        values,
        replySignature: replySignature,
      );
    }
    await _ensureLinuxClient();
    return _linuxScreensaver!.callMethod(
      _screensaverName,
      method,
      values,
      replySignature: replySignature,
    );
  }

  Future<void> _inhibitLinux() async {
    if (_active) return;
    try {
      final response = await _linuxCall('Inhibit', const [
        DBusString('Dacx'),
        DBusString('Playing media'),
      ], replySignature: DBusSignature('u'));
      _cookie = response.returnValues[0].asUint32();
      _active = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: idle inhibit unavailable: $e');
      }
    }
  }

  Future<void> _uninhibitLinux() async {
    final cookie = _cookie;
    _cookie = null;
    _active = false;
    if (cookie == null) return;
    try {
      await _linuxCall('UnInhibit', [DBusUint32(cookie)]);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: idle uninhibit failed: $e');
      }
    }
  }

  Future<void> dispose() async {
    if (Platform.isLinux) {
      await _uninhibitLinux();
      final client = _linuxClient;
      _linuxClient = null;
      _linuxScreensaver = null;
      if (client != null && linuxClientForTesting == null) {
        try {
          await client.close();
        } catch (_) {}
      }
      return;
    }
    if (_active && (Platform.isWindows || Platform.isMacOS)) {
      await _setNativeInhibit(false);
    }
  }

  /// Parses `uint32 N` from dbus-send `--print-reply` stdout (legacy helper).
  @visibleForTesting
  static int? parseUint32ReplyForTest(String stdout) {
    final match = RegExp(r'uint32\s+(\d+)').firstMatch(stdout);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
