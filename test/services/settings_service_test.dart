import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/services/settings_service.dart';

void main() {
  group('SettingsService.recentFiles', () {
    test('returns empty list for invalid JSON', () async {
      SharedPreferences.setMockInitialValues({'recent_files': 'not-json'});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.recentFiles, isEmpty);
    });

    test('returns empty list when payload is not a list', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode({'path': '/tmp/file.mp3'}),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.recentFiles, isEmpty);
    });

    test('keeps only non-empty string entries', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode([
          '/tmp/one.mp3',
          42,
          null,
          '   ',
          '/tmp/two.flac',
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.recentFiles, ['/tmp/one.mp3', '/tmp/two.flac']);
    });
  });
}
