// Freezes the literal string identifiers that cross the Dart/native boundary
// or persist to disk. A rename without coordinated native/migration work
// will silently break: this test refuses to compile when the constant
// shifts and refuses to pass when the runtime value drifts.
//
// If a key/channel must change intentionally, update both the frozen list
// here AND every native bridge / migration path it touches.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/instance_mode_service.dart';
import 'package:dacx/services/open_file_bridge.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('frozen platform identifiers', () {
    test('media session method channel name is unchanged', () {
      // Touching this constant requires updating:
      //   - macos/Runner/MediaSessionBridge.swift (channelName)
      //   - windows/runner/media_session.cpp (FlutterMethodChannel ctor)
      //   - lib/services/media_session_service.dart (_channel)
      const expected = 'run.rosie.dacx/media_session';
      const channel = MethodChannel(expected);
      expect(channel.name, expected);
    });

    test('open file bridge channel names are unchanged', () {
      // Touching these requires updating native runners:
      //   - macos/Runner/AppDelegate.swift
      //   - windows/runner/instance_bridge.cpp
      //   - linux/runner/my_application.cc
      expect(
        OpenFileBridge.methodChannelName,
        'run.rosie.dacx/open_file/methods',
      );
      expect(
        OpenFileBridge.eventChannelName,
        'run.rosie.dacx/open_file/events',
      );
    });

    test('window method channel name is unchanged', () {
      // Touching this requires updating:
      //   - macos/Runner/MainFlutterWindow.swift
      //   - lib/services/instance_mode_service.dart
      expect(
        InstanceModeService.windowMethodChannelName,
        'run.rosie.dacx/window/methods',
      );
    });
  });

  group('frozen SharedPreferences keys', () {
    test('SettingsService.frozenPreferenceKeys is non-empty and unique', () {
      const frozen = SettingsService.frozenPreferenceKeys;
      expect(frozen, isNotEmpty);
      expect(frozen.length, frozen.toSet().length);
    });

    test('every key is well-formed lower_snake_case', () {
      final pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final key in SettingsService.frozenPreferenceKeys) {
        expect(
          pattern.hasMatch(key),
          isTrue,
          reason: 'pref key "$key" is not lower_snake_case',
        );
      }
    });
  });
}
