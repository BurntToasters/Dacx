import 'dart:convert';
import 'dart:io';

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

    test('keeps only existing non-empty string entries', () async {
      final tempDir = await Directory.systemTemp.createTemp('dacx-settings-');
      addTearDown(() => tempDir.delete(recursive: true));
      final existing = File('${tempDir.path}/track.mp3')
        ..writeAsStringSync('x');
      final missing = '${tempDir.path}/missing.mp3';

      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode([existing.path, missing, 42, null, '   ']),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.recentFiles, [existing.path]);
    });

    test('pruneRecentFiles removes missing entries from storage', () async {
      final tempDir = await Directory.systemTemp.createTemp('dacx-settings-');
      addTearDown(() => tempDir.delete(recursive: true));
      final existing = File('${tempDir.path}/ok.flac')..writeAsStringSync('x');
      final missing = '${tempDir.path}/gone.flac';

      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode([existing.path, missing]),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      final changed = service.pruneRecentFiles(notifyListeners: false);

      expect(changed, isTrue);
      expect(service.recentFiles, [existing.path]);
      expect(prefs.getString('recent_files'), jsonEncode([existing.path]));
    });

    test('addRecentFile works when existing storage list is present', () async {
      final tempDir = await Directory.systemTemp.createTemp('dacx-settings-');
      addTearDown(() => tempDir.delete(recursive: true));
      final existing = File('${tempDir.path}/existing.mp3')
        ..writeAsStringSync('x');
      final incoming = File('${tempDir.path}/incoming.mp3')
        ..writeAsStringSync('x');

      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode([existing.path]),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.addRecentFile(incoming.path);

      expect(service.recentFiles, [incoming.path, existing.path]);
    });
  });

  group('SettingsService.lastOpenDirectory', () {
    test('returns null for missing or invalid directories', () async {
      SharedPreferences.setMockInitialValues({
        'last_open_directory': '/definitely/missing/path',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.lastOpenDirectory, isNull);
    });

    test('persists and reads existing directory path', () async {
      final tempDir = await Directory.systemTemp.createTemp('dacx-last-dir-');
      addTearDown(() => tempDir.delete(recursive: true));

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.lastOpenDirectory = tempDir.path;

      expect(service.lastOpenDirectory, tempDir.path);
      expect(prefs.getString('last_open_directory'), tempDir.path);
    });
  });
}
