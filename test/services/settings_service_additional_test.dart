import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/services/settings_service.dart';

void main() {
  group('SettingsService additional coverage', () {
    test(
      'migrates resume_positions_v1 map to resume_positions_v2 payload',
      () async {
        SharedPreferences.setMockInitialValues({
          'playback_volume': 90.0,
          'resume_positions_v1': jsonEncode({
            '/ok.mp3': 42000,
            '/zero.mp3': 0,
            '/neg.mp3': -5,
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        SettingsService(prefs);

        expect(prefs.getString('resume_positions_v1'), isNull);
        final raw = prefs.getString('resume_positions_v2');
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        final ok = decoded['/ok.mp3'] as Map<String, dynamic>;
        expect(ok['p'], 42000);
        expect(ok['t'], isA<int>());
        expect(ok['t'] as int, greaterThan(0));
        expect(decoded.containsKey('/zero.mp3'), isFalse);
        expect(decoded.containsKey('/neg.mp3'), isFalse);
      },
    );

    test(
      'drops malformed resume_positions_v1 payload during migration',
      () async {
        SharedPreferences.setMockInitialValues({
          'playback_volume': 90.0,
          'resume_positions_v1': jsonEncode(['/not-a-map']),
        });
        final prefs = await SharedPreferences.getInstance();
        SettingsService(prefs);

        expect(prefs.getString('resume_positions_v1'), isNull);
        expect(prefs.getString('resume_positions_v2'), isNull);
      },
    );

    test('lastOpenDirectory rejects unsafe traversal payload', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.lastOpenDirectory = '../escape';
      expect(service.lastOpenDirectory, isNull);
      expect(prefs.getString('last_open_directory'), isNull);
    });

    test(
      'addRecentFile trims list to maxRecentFiles and prunes bookmarks',
      () async {
        final source = List<String>.generate(
          SettingsService.maxRecentFiles + 4,
          (i) => '/fake/path_$i.mp3',
        );
        SharedPreferences.setMockInitialValues({
          'file_bookmarks_v1': jsonEncode({
            '/fake/path_0.mp3': '00:10',
            '/fake/path_1.mp3': '00:20',
            '/orphan.mp3': '01:00',
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        for (final path in source) {
          service.addRecentFile(path);
        }

        expect(service.recentFiles, hasLength(SettingsService.maxRecentFiles));
        expect(service.recentFiles.first, '/fake/path_23.mp3');
        expect(service.recentFiles.last, '/fake/path_4.mp3');

        final bookmarksRaw = prefs.getString('file_bookmarks_v1');
        // All seeded bookmarks should be pruned by the time recents reaches
        // final capped set.
        expect(bookmarksRaw, isNull);
      },
    );

    test('bookmark APIs round-trip and remove values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.setFileBookmark('/movie.mkv', '01:23');
      expect(service.fileBookmark('/movie.mkv'), '01:23');

      service.removeFileBookmark('/movie.mkv');
      expect(service.fileBookmark('/movie.mkv'), isNull);
      expect(prefs.getString('file_bookmarks_v1'), isNull);
    });

    test('bookmark APIs ignore invalid payloads and blanks', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.setFileBookmark('../escape.mkv', '11:11');
      service.setFileBookmark('/ok.mkv', '');
      expect(service.fileBookmark('/ok.mkv'), isNull);
      expect(service.fileBookmark('   '), isNull);
      expect(prefs.getString('file_bookmarks_v1'), isNull);
    });

    test('pruneRecentFiles removes key when every entry is missing', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode(['/missing-1.mp3', '/missing-2.mp3']),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      final changed = service.pruneRecentFiles(notifyListeners: false);
      expect(changed, isTrue);
      expect(service.recentFiles, isEmpty);
      expect(prefs.getString('recent_files'), isNull);
    });

    test(
      'clearRecentFiles clears both recents and bookmarks and notifies',
      () async {
        SharedPreferences.setMockInitialValues({
          'recent_files': jsonEncode(['/a.mp3']),
          'file_bookmarks_v1': jsonEncode({'/a.mp3': '00:10'}),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);
        var notifications = 0;
        service.addListener(() => notifications++);

        service.clearRecentFiles();

        expect(prefs.getString('recent_files'), isNull);
        expect(prefs.getString('file_bookmarks_v1'), isNull);
        expect(notifications, 1);
      },
    );

    test('eqEnabled and eqPreset persist and notify', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(service.eqEnabled, isFalse);
      expect(service.eqPreset, 'flat');

      service.eqEnabled = true;
      service.eqPreset = 'rock';

      expect(service.eqEnabled, isTrue);
      expect(service.eqPreset, 'rock');
      expect(notifications, 2);
    });

    test(
      'eqBands accepts only numeric entries, clamps, pads, and truncates',
      () async {
        SharedPreferences.setMockInitialValues({
          'eq_bands': jsonEncode([1, 2, 'x', 99, -99, 6, 7, 8, 9, 10, 11, 12]),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        final bands = service.eqBands;
        expect(bands, hasLength(SettingsService.eqBandCount));
        expect(bands, [1.0, 2.0, 12.0, -12.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]);
      },
    );

    test(
      'eqBands falls back to zeros when stored payload is not a list',
      () async {
        SharedPreferences.setMockInitialValues({
          'eq_bands': jsonEncode({'not': 'a-list'}),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        expect(
          service.eqBands,
          List<double>.filled(SettingsService.eqBandCount, 0),
        );
      },
    );

    test(
      'screenshotDir reads/writes valid path and removes invalid path',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dacx-shot-dir-');
        addTearDown(() => tempDir.delete(recursive: true));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        service.screenshotDir = ' ${tempDir.path} ';
        expect(service.screenshotDir, tempDir.path);
        expect(prefs.getString('screenshot_dir'), tempDir.path);

        service.screenshotDir = '../escape';
        expect(service.screenshotDir, isNull);
        expect(prefs.getString('screenshot_dir'), isNull);
      },
    );

    test('screenshotDir getter rejects non-existent stored path', () async {
      SharedPreferences.setMockInitialValues({
        'screenshot_dir': '/definitely/missing/path',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.screenshotDir, isNull);
    });

    test(
      'screenshotFormat falls back to png and ignores invalid setter values',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);
        var notifications = 0;
        service.addListener(() => notifications++);

        expect(service.screenshotFormat, 'png');

        service.screenshotFormat = 'jpg';
        expect(service.screenshotFormat, 'jpg');

        service.screenshotFormat = 'gif';
        expect(service.screenshotFormat, 'jpg');
        expect(notifications, 1);
      },
    );

    test('seekPreviewEnabled setter is idempotent for same value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(service.seekPreviewEnabled, isFalse);
      service.seekPreviewEnabled = false;
      service.seekPreviewEnabled = true;
      service.seekPreviewEnabled = true;

      expect(service.seekPreviewEnabled, isTrue);
      expect(notifications, 1);
    });

    test('audioWaveformEnabled is gated by experimentalFeaturesEnabled',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.audioWaveformEnabled = true;
      expect(service.audioWaveformEnabled, isFalse);

      service.experimentalFeaturesEnabled = true;
      expect(service.audioWaveformEnabled, isTrue);

      service.experimentalFeaturesEnabled = false;
      expect(service.audioWaveformEnabled, isFalse);
    });

    test('multiAudioMix is gated by experimentalFeaturesEnabled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.multiAudioMix = true;
      expect(service.multiAudioMix, isFalse);

      service.experimentalFeaturesEnabled = true;
      expect(service.multiAudioMix, isTrue);
    });

    test(
      'keybinds decode filters non-string list entries and malformed payload',
      () async {
        SharedPreferences.setMockInitialValues({
          'keybinds_v1': jsonEncode({
            'play_pause': ['Space', 7, null],
            'seek_forward': 'not-a-list',
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        expect(service.keybinds['play_pause'], ['Space']);
        expect(service.keybinds.containsKey('seek_forward'), isFalse);

        await prefs.setString('keybinds_v1', jsonEncode(['broken']));
        final fresh = SettingsService(await SharedPreferences.getInstance());
        expect(fresh.keybinds, isEmpty);
      },
    );

    test('playlistShuffle persists boolean value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.playlistShuffle, isFalse);
      service.playlistShuffle = true;
      expect(service.playlistShuffle, isTrue);
    });

    test(
      'resume positions decode valid entries and ignore invalid entries',
      () async {
        SharedPreferences.setMockInitialValues({
          'resume_positions_v2': jsonEncode({
            '/ok.mp3': {'p': 1000, 't': 100},
            '/bad-p.mp3': {'p': 0, 't': 100},
            '/bad-t.mp3': {'p': 1000, 't': 0},
            '/bad-shape.mp3': 123,
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        expect(service.resumePositionFor('/ok.mp3'), 1000);
        expect(service.resumePositionFor('/bad-p.mp3'), isNull);
        expect(service.resumePositionFor('/bad-t.mp3'), isNull);
        expect(service.resumePositionFor('/bad-shape.mp3'), isNull);
      },
    );

    test(
      'resumePositionFor updates last-access timestamp when stale',
      () async {
        SharedPreferences.setMockInitialValues({
          'resume_positions_v2': jsonEncode({
            '/old.mp3': {'p': 3210, 't': 1},
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService(prefs);

        final value = service.resumePositionFor('/old.mp3');
        expect(value, 3210);

        service.flushResumePositions();
        final raw = prefs.getString('resume_positions_v2');
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        final old = decoded['/old.mp3'] as Map<String, dynamic>;
        expect(old['t'] as int, greaterThan(1));
      },
    );

    test('saveResumePosition ignores unsafe file paths', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      service.saveResumePosition('../escape.mp3', 1000);
      expect(service.resumePositionFor('../escape.mp3'), isNull);
      expect(prefs.getString('resume_positions_v2'), isNull);
    });
  });
}
