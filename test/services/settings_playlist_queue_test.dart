import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/services/settings_service.dart';

void main() {
  group('SettingsService empty state tip', () {
    test('empty state tip flag defaults false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      expect(settings.emptyStateTipDismissed, isFalse);
      settings.emptyStateTipDismissed = true;
      expect(settings.emptyStateTipDismissed, isTrue);
    });
  });
}
