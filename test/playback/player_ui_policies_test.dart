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
  });
}
