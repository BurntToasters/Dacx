import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/services/settings_service.dart';

void main() {
  group('SettingsService schema migrations', () {
    test('fresh install stamps current schema version', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.schemaVersion, SettingsService.currentSchemaVersion);
      expect(
        prefs.getInt('settings_schema_version'),
        SettingsService.currentSchemaVersion,
      );
    });

    test(
      'existing install without schema key gets migrated up to current version',
      () async {
        // Simulate a pre-framework install: real settings present but no
        // schema marker.
        SharedPreferences.setMockInitialValues({
          'playback_volume': 75.0,
          'appearance_theme': 'dark',
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        expect(service.schemaVersion, SettingsService.currentSchemaVersion);
        // Pre-existing values are preserved through the baseline migration.
        expect(service.volume, 75.0);
      },
    );

    test('install already at current version is a no-op', () async {
      SharedPreferences.setMockInitialValues({
        'settings_schema_version': SettingsService.currentSchemaVersion,
        'playback_volume': 42.0,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.schemaVersion, SettingsService.currentSchemaVersion);
      expect(service.volume, 42.0);
    });

    test('install at a future version is left untouched', () async {
      // Defensive: if a user downgrades the app, we must not clobber a
      // newer schema with old migrations.
      const future = SettingsService.currentSchemaVersion + 5;
      SharedPreferences.setMockInitialValues({
        'settings_schema_version': future,
      });
      final prefs = await SharedPreferences.getInstance();
      // Construction should not throw and must not rewrite the version.
      SettingsService(prefs);
      expect(prefs.getInt('settings_schema_version'), future);
    });
  });
}
