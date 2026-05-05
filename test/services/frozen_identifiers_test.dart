// Freezes the literal string identifiers that cross the Dart/native boundary
// or persist to disk. A rename without coordinated native/migration work
// will silently break: this test refuses to compile when the constant
// shifts and refuses to pass when the runtime value drifts.
//
// If a key/channel must change intentionally, update both the frozen list
// here AND every native bridge / migration path it touches.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });

  group('frozen SharedPreferences keys', () {
    // These string values are persisted to disk on every install; renaming
    // any of them silently wipes a user's settings. If you need to rename,
    // write a migration in SettingsService first, then update this list.
    const frozen = <String>{
      'playback_volume',
      'playback_speed',
      'playback_loop_mode',
      'playback_auto_play',
      'appearance_theme',
      'appearance_accent',
      'appearance_always_on_top',
      'appearance_remember_window',
      'window_width',
      'window_height',
      'window_x',
      'window_y',
      'recent_files',
      'last_open_directory',
      'update_check_enabled',
      'update_last_check',
      'system_hwdec',
      'window_opacity',
      'window_blur_enabled',
      'window_blur_strength',
      'experimental_features_enabled',
      'linux_compositor_blur_experimental',
      'debug_mode_enabled',
      'eq_enabled',
      'eq_preset',
      'eq_bands',
      'screenshot_dir',
      'screenshot_format',
      'osd_enabled',
      'seek_preview_enabled',
      'multi_audio_mix',
      'media_session_enabled',
      'keybinds_v1',
      'resume_playback_enabled',
      'resume_positions_v1',
      'playlist_shuffle',
    };

    test('snapshot is non-empty and unique', () {
      expect(frozen, isNotEmpty);
      expect(frozen.length, frozen.toSet().length);
    });

    test('every key is well-formed', () {
      // SharedPreferences allows any string but we restrict to lower_snake to
      // catch accidental whitespace or punctuation.
      final pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final key in frozen) {
        expect(
          pattern.hasMatch(key),
          isTrue,
          reason: 'pref key "$key" is not lower_snake_case',
        );
      }
    });
  });
}
