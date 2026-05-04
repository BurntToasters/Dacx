import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

    test(
      'returns trimmed non-empty string entries without fs checks',
      () async {
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

        expect(service.recentFiles, [existing.path, missing]);
      },
    );

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
    test('returns stored path value without fs checks', () async {
      SharedPreferences.setMockInitialValues({
        'last_open_directory': '/definitely/missing/path',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.lastOpenDirectory, '/definitely/missing/path');
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

  group('SettingsService.general settings', () {
    test('reads defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.volume, 100.0);
      expect(service.speed, 1.0);
      expect(service.loopMode, LoopMode.none);
      expect(service.autoPlay, isTrue);
      expect(service.themeMode, ThemeMode.dark);
      expect(service.accentColor, AccentColor.blueGrey);
      expect(service.alwaysOnTop, isFalse);
      expect(service.rememberWindow, isTrue);
      expect(service.windowSize, isNull);
      expect(service.windowPosition, isNull);
      expect(service.updateCheckEnabled, isTrue);
      expect(service.lastUpdateCheck, 0);
      expect(service.shouldCheckForUpdate, isTrue);
      expect(service.hwDec, 'auto');
      expect(service.windowOpacity, 1.0);
      expect(service.windowBlurEnabled, isFalse);
      expect(service.windowBlurStrength, 0.55);
      expect(service.experimentalFeaturesEnabled, isFalse);
      expect(service.linuxCompositorBlurExperimental, isFalse);
      expect(service.debugModeEnabled, isFalse);
    });

    test('persists setters and reads values back', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.volume = 75;
      service.speed = 1.25;
      service.loopMode = LoopMode.loop;
      service.autoPlay = false;
      service.themeMode = ThemeMode.system;
      service.accentColor = AccentColor.teal;
      service.alwaysOnTop = true;
      service.rememberWindow = false;
      service.saveWindowSize(const Size(1280, 720));
      service.saveWindowPosition(const Offset(55, 77));
      service.updateCheckEnabled = false;
      service.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      service.hwDec = 'no';
      service.windowOpacity = 0.8;
      service.windowBlurEnabled = true;
      service.windowBlurStrength = 0.9;
      service.experimentalFeaturesEnabled = true;
      service.linuxCompositorBlurExperimental = true;
      service.debugModeEnabled = true;

      expect(service.volume, 75);
      expect(service.speed, 1.25);
      expect(service.loopMode, LoopMode.loop);
      expect(service.autoPlay, isFalse);
      expect(service.themeMode, ThemeMode.system);
      expect(service.accentColor, AccentColor.teal);
      expect(service.alwaysOnTop, isTrue);
      expect(service.rememberWindow, isFalse);
      expect(service.windowSize, const Size(1280, 720));
      expect(service.windowPosition, const Offset(55, 77));
      expect(service.updateCheckEnabled, isFalse);
      expect(service.shouldCheckForUpdate, isFalse);
      expect(service.hwDec, 'no');
      expect(service.windowOpacity, 0.8);
      expect(service.windowBlurEnabled, isTrue);
      expect(service.windowBlurStrength, 0.9);
      expect(service.experimentalFeaturesEnabled, isTrue);
      expect(service.linuxCompositorBlurExperimental, isTrue);
      expect(service.debugModeEnabled, isTrue);
    });

    test('clamps opacity and blur strength ranges', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.windowOpacity = 0.1;
      expect(service.windowOpacity, 0.65);
      service.windowOpacity = 2.0;
      expect(service.windowOpacity, 1.0);

      service.windowBlurStrength = -1.0;
      expect(service.windowBlurStrength, 0.0);
      service.windowBlurStrength = 2.0;
      expect(service.windowBlurStrength, 1.0);
    });

    test('falls back for unknown enum backing values', () async {
      SharedPreferences.setMockInitialValues({
        'playback_loop_mode': 'wat',
        'appearance_theme': 'wat',
        'appearance_accent': 'wat',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.loopMode, LoopMode.none);
      expect(service.themeMode, ThemeMode.dark);
      expect(service.accentColor, AccentColor.blueGrey);
    });

    test('resetAll clears persisted state', () async {
      SharedPreferences.setMockInitialValues({'playback_volume': 77.0});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.volume, 77.0);
      await service.resetAll();
      expect(service.volume, 100.0);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('SettingsService.eqBands', () {
    test('returns zeroed bands when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      expect(service.eqBands, List<double>.filled(10, 0));
    });

    test('clamps gains to +/-12 dB on write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.eqBands = List<double>.filled(10, 99.0);
      expect(service.eqBands, List<double>.filled(10, 12.0));
      service.eqBands = List<double>.filled(10, -99.0);
      expect(service.eqBands, List<double>.filled(10, -12.0));
    });

    test('falls back to zeros on corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({'eq_bands': 'not-json'});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      expect(service.eqBands, List<double>.filled(10, 0));
    });

    test('cached read does not hit prefs after first call', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      // Mutating the underlying pref directly should NOT change the cached value.
      await prefs.setString('eq_bands', jsonEncode(List<double>.filled(10, 0)));
      expect(service.eqBands, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });
  });

  group('SettingsService.keybinds', () {
    test('empty when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      expect(service.keybinds, isEmpty);
    });

    test('round-trips action -> accelerators map', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.keybinds = {
        'play_pause': ['Space', 'K'],
        'seek_forward': ['Arrow Right'],
      };
      expect(service.keybinds['play_pause'], ['Space', 'K']);
      expect(service.keybinds['seek_forward'], ['Arrow Right']);
    });

    test('returns empty map on corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({'keybinds_v1': 'broken'});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      expect(service.keybinds, isEmpty);
    });

    test('resetKeybinds clears stored value and cache', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.keybinds = {
        'a': ['X'],
      };
      service.resetKeybinds();
      expect(service.keybinds, isEmpty);
      expect(prefs.getString('keybinds_v1'), isNull);
    });
  });

  group('SettingsService.resumePositions', () {
    test('returns null when resume disabled', () async {
      SharedPreferences.setMockInitialValues({
        'resume_playback_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.saveResumePosition('/a.mp3', 5000);
      expect(service.resumePositionFor('/a.mp3'), isNull);
    });

    test('save and read round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.saveResumePosition('/a.mp3', 12345);
      expect(service.resumePositionFor('/a.mp3'), 12345);
    });

    test('null/zero clears the entry', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.saveResumePosition('/a.mp3', 12345);
      service.saveResumePosition('/a.mp3', null);
      expect(service.resumePositionFor('/a.mp3'), isNull);
      service.saveResumePosition('/a.mp3', 99);
      service.saveResumePosition('/a.mp3', 0);
      expect(service.resumePositionFor('/a.mp3'), isNull);
    });

    test('LRU prunes oldest beyond maxResumeEntries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      for (var i = 0; i < SettingsService.maxResumeEntries + 5; i++) {
        service.saveResumePosition('/track$i.mp3', i + 1);
      }
      expect(service.resumePositionFor('/track0.mp3'), isNull);
      expect(
        service.resumePositionFor(
          '/track${SettingsService.maxResumeEntries + 4}.mp3',
        ),
        isNotNull,
      );
    });

    test('corrupt stored JSON is treated as empty', () async {
      SharedPreferences.setMockInitialValues({
        'resume_positions_v1': 'definitely-not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      expect(service.resumePositionFor('/a.mp3'), isNull);
    });

    test('clearAllResumePositions removes everything', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      service.saveResumePosition('/a.mp3', 100);
      service.saveResumePosition('/b.mp3', 200);
      service.clearAllResumePositions();
      expect(service.resumePositionFor('/a.mp3'), isNull);
      expect(service.resumePositionFor('/b.mp3'), isNull);
    });
  });
}
