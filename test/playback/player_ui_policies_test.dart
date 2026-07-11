import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/playback/player_ui_policies.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  Future<SettingsService> settingsWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    return SettingsService(shared);
  }

  group('PlayerUiPolicies', () {
    test('showSeekPreview requires video file and enabled setting', () async {
      final settings = await settingsWith({'seek_preview_enabled': true});
      expect(
        PlayerUiPolicies.showSeekPreview(
          settings: settings,
          isAudioFile: false,
        ),
        isTrue,
      );
      expect(
        PlayerUiPolicies.showSeekPreview(settings: settings, isAudioFile: true),
        isFalse,
      );
    });

    test('showAudioSpectrum requires audio file and enabled setting', () async {
      final settings = await settingsWith({
        'experimental_features_enabled': true,
        'audio_waveform_enabled': true,
      });
      expect(
        PlayerUiPolicies.showAudioSpectrum(
          settings: settings,
          isAudioFile: true,
        ),
        isTrue,
      );
      expect(
        PlayerUiPolicies.showAudioSpectrum(
          settings: settings,
          isAudioFile: false,
        ),
        isFalse,
      );
    });

    test('spectrumHeight is 40 when visualizer enabled else 0', () async {
      final off = await settingsWith({'audio_waveform_enabled': false});
      final on = await settingsWith({
        'experimental_features_enabled': true,
        'audio_waveform_enabled': true,
      });
      expect(PlayerUiPolicies.spectrumHeight(off), 0.0);
      expect(PlayerUiPolicies.spectrumHeight(on), 40.0);
    });
  });
}
