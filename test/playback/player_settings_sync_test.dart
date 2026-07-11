import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/playback/player_settings_sync.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  Future<SettingsService> settingsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  group('PlayerSettingsSync.diff', () {
    test('returns empty delta when nothing changed', () async {
      final settings = await settingsWith({
        'playback_speed': 1.0,
        'playback_loop_mode': 'none',
      });
      const state = PlayerSettingsSyncState(
        lastSpeed: 1.0,
        lastLoopMode: LoopMode.none,
        lastAlwaysOnTop: false,
        lastMediaSessionEnabled: true,
        lastPlaylistShuffle: false,
        lastMultiAudioMix: false,
        lastAudioWaveformEnabled: false,
        lastEqEnabled: false,
        lastEqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        lastHwDec: 'auto',
      );

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.isEmpty, isTrue);
      expect(next, state);
    });

    test('detects speed and loop changes', () async {
      final settings = await settingsWith({
        'playback_speed': 1.5,
        'playback_loop_mode': 'single',
      });
      const state = PlayerSettingsSyncState(
        lastSpeed: 1.0,
        lastLoopMode: LoopMode.none,
      );

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.speed, 1.5);
      expect(delta.loopMode, LoopMode.single);
      expect(delta.rebuildUi, isTrue);
      expect(next.lastSpeed, 1.5);
      expect(next.lastLoopMode, LoopMode.single);
    });

    test('detects audio filter changes from EQ band edits', () async {
      final settings = await settingsWith({
        'eq_enabled': true,
        'eq_bands': '[4,0,0,0,0,0,0,0,0,0]',
      });
      settings.eqEnabled = true;
      settings.eqBands = const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0];

      const state = PlayerSettingsSyncState(
        lastEqEnabled: false,
        lastEqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );

      final (delta, _) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.audioFilters, isTrue);
    });

    test('detects experimental multi-audio mix toggle', () async {
      final settings = await settingsWith({
        'experimental_features_enabled': true,
        'multi_audio_mix': true,
      });
      const state = PlayerSettingsSyncState(lastMultiAudioMix: false);

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.multiAudioMix, isTrue);
      expect(next.lastMultiAudioMix, isTrue);
    });

    test('detects always-on-top toggle', () async {
      final settings = await settingsWith({'appearance_always_on_top': true});
      const state = PlayerSettingsSyncState(lastAlwaysOnTop: false);

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.alwaysOnTop, isTrue);
      expect(next.lastAlwaysOnTop, isTrue);
    });

    test('detects media session toggle', () async {
      final settings = await settingsWith({'media_session_enabled': false});
      const state = PlayerSettingsSyncState(lastMediaSessionEnabled: true);

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.mediaSessionEnabled, isFalse);
      expect(next.lastMediaSessionEnabled, isFalse);
    });

    test('detects playlist shuffle toggle', () async {
      final settings = await settingsWith({'playlist_shuffle': true});
      const state = PlayerSettingsSyncState(lastPlaylistShuffle: false);

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.playlistShuffle, isTrue);
      expect(next.lastPlaylistShuffle, isTrue);
    });

    test('detects hwDec change', () async {
      final settings = await settingsWith({'system_hwdec': 'no'});
      const state = PlayerSettingsSyncState(lastHwDec: 'auto');

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.hwDec, 'no');
      expect(next.lastHwDec, 'no');
    });

    test('detects audio waveform-only change', () async {
      final settings = await settingsWith({
        'experimental_features_enabled': true,
        'audio_waveform_enabled': true,
      });
      const state = PlayerSettingsSyncState(lastAudioWaveformEnabled: false);

      final (delta, next) = PlayerSettingsSync.diff(
        state: state,
        settings: settings,
      );

      expect(delta.audioFilters, isTrue);
      expect(next.lastAudioWaveformEnabled, isTrue);
    });
  });
}
