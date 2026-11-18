import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dacx/services/app_exit_hooks.dart';
import 'package:dacx/services/instance_mode_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../support/audit9_report.dart';

class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore(Map<String, Object> seed)
    : values = {for (final e in seed.entries) e.key: e.value},
      super.withData({
        for (final e in seed.entries) 'flutter.${e.key}': e.value,
      });

  final List<String> writes = [];
  final Map<String, Object> values;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final name = key.replaceFirst('flutter.', '');
    writes.add(name);
    values[name] = value;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    final name = key.replaceFirst('flutter.', '');
    writes.add('-$name');
    values.remove(name);
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    values.clear();
    return super.clear();
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) {
    values.clear();
    return super.clearWithParameters(parameters);
  }

  int count(String key) => writes.where((w) => w == key).length;
}

class _Env {
  _Env(this.store, this.prefs, this.settings);

  final _CountingStore store;
  final SharedPreferences prefs;
  final SettingsService settings;
}

Future<_Env> _make({
  Map<String, Object> seed = const {},
  bool autoDispose = true,
}) async {
  final store = _CountingStore(seed);
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  store.writes.clear();
  if (autoDispose) addTearDown(settings.dispose);
  return _Env(store, prefs, settings);
}

Future<SettingsService> _reopen(_CountingStore store) async {
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  addTearDown(settings.dispose);
  return settings;
}

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

const _justBefore = Duration(milliseconds: 799);
const _oneMs = Duration(milliseconds: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'storage',
    expectedIds: [
      'M3.1',
      'M3.2',
      'M3.3',
      'M3.4',
      'M7.1',
      'M7.2',
      'M7.3',
      'M7.4',
      'M7.5',
      'M7.6',
      'M13.1',
      'M13.2',
      'M13.3',
      'M13.4',
      'M13.5',
      'M13.6',
      'M13.7',
      'M13.8',
      'M13.9',
      'M14.1',
      'M14.2',
      'M14.3',
      'M14.4',
      'M14.5',
      'M15.1',
      'M15.2',
      'M31.1',
      'M31.2',
    ],
  );
  tearDownAll(report.write);

  late Directory flagDir;
  setUp(() {
    flagDir = Directory.systemTemp.createTempSync('dacx-a9-flag-');
    InstanceModeService.setFlagDirForTesting(flagDir.path);
  });
  tearDown(() {
    InstanceModeService.setFlagDirForTesting(null);
    if (flagDir.existsSync()) flagDir.deleteSync(recursive: true);
  });

  group('finding 3: windowSize validation and window_maximized', () {
    test('M3.1 non-finite stored size is rejected', () async {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final badWidth = await _make(
          seed: {'window_width': bad, 'window_height': 700.0},
        );
        expect(badWidth.settings.windowSize, isNull);
        final badHeight = await _make(
          seed: {'window_width': 900.0, 'window_height': bad},
        );
        expect(badHeight.settings.windowSize, isNull);
      }
      report.pass('M3.1');
    });

    test('M3.2 stored size below 480x320 is rejected per axis', () async {
      for (final seed in <Map<String, Object>>[
        {'window_width': 160.0, 'window_height': 700.0},
        {'window_width': 900.0, 'window_height': 28.0},
        {'window_width': 479.0, 'window_height': 320.0},
        {'window_width': 480.0, 'window_height': 319.0},
        {'window_width': 0.0, 'window_height': 0.0},
        {'window_width': -10.0, 'window_height': 700.0},
      ]) {
        final env = await _make(seed: seed);
        expect(env.settings.windowSize, isNull, reason: '$seed');
      }
      report.pass('M3.2');
    });

    test('M3.3 valid stored size and position still restore', () async {
      final exact = await _make(
        seed: {
          'window_width': 480.0,
          'window_height': 320.0,
          'window_x': -1200.0,
          'window_y': 40.0,
        },
      );
      expect(exact.settings.windowSize, const Size(480, 320));
      expect(exact.settings.windowPosition, const Offset(-1200, 40));
      final large = await _make(
        seed: {'window_width': 1920.0, 'window_height': 1080.0},
      );
      expect(large.settings.windowSize, const Size(1920, 1080));
      expect(large.settings.windowPosition, isNull);
      report.pass('M3.3');
    });

    test('M3.4 window_maximized defaults, round-trips and is frozen', () async {
      final env = await _make();
      expect(env.settings.windowMaximized, isFalse);
      env.settings.windowMaximized = true;
      expect(env.settings.windowMaximized, isTrue);
      await env.settings.flushPendingWrites();
      final reopened = await _reopen(env.store);
      expect(reopened.windowMaximized, isTrue);
      reopened.windowMaximized = false;
      expect(reopened.windowMaximized, isFalse);
      await reopened.flushPendingWrites();
      expect((await _reopen(env.store)).windowMaximized, isFalse);
      expect(
        SettingsService.frozenPreferenceKeys,
        contains('window_maximized'),
      );
      expect(SettingsService.currentSchemaVersion, 4);
      report.pass('M3.4');
    });
  });

  group('finding 7: screenshot folder bookmark', () {
    test('M7.1 bookmark survives addRecentFile pruning', () async {
      final shots = _tempDir('dacx-a9-shots-');
      final env = await _make();
      final s = env.settings;
      s.screenshotDir = shots.path;
      s.setFileBookmark(shots.path, 'shot-bm');
      s.setFileBookmark('/other/unrelated', 'other-bm');
      s.setFileBookmark('/music/a.mp3', 'a-bm');

      s.addRecentFile('/music/a.mp3');

      expect(s.screenshotDir, shots.path);
      expect(s.fileBookmark(shots.path), 'shot-bm');
      expect(s.fileBookmark('/music/a.mp3'), 'a-bm');
      expect(s.fileBookmark('/other/unrelated'), isNull);
      report.pass('M7.1');
    });

    test('M7.2 bookmark survives clearRecentFiles', () async {
      final shots = _tempDir('dacx-a9-shots-');
      final env = await _make();
      final s = env.settings;
      s.screenshotDir = shots.path;
      s.setFileBookmark(shots.path, 'shot-bm');
      s.addRecentFile('/music/a.mp3');
      s.setFileBookmark('/music/a.mp3', 'a-bm');

      s.clearRecentFiles();

      expect(s.recentFiles, isEmpty);
      expect(s.fileBookmark(shots.path), 'shot-bm');
      expect(s.fileBookmark('/music/a.mp3'), isNull);
      expect(env.store.values.containsKey('file_bookmarks_v1'), isTrue);
      report.pass('M7.2');
    });

    test('M7.3 bookmark survives pruneRecentFiles', () async {
      final shots = _tempDir('dacx-a9-shots-');
      final env = await _make(
        seed: {
          'recent_files': jsonEncode(['/definitely/missing/a9.mp3']),
        },
      );
      final s = env.settings;
      s.screenshotDir = shots.path;
      s.setFileBookmark(shots.path, 'shot-bm');
      s.setFileBookmark('/definitely/missing/a9.mp3', 'gone-bm');

      final changed = await s.pruneRecentFiles(notifyListeners: false);

      expect(changed, isTrue);
      expect(s.recentFiles, isEmpty);
      expect(s.fileBookmark(shots.path), 'shot-bm');
      expect(s.fileBookmark('/definitely/missing/a9.mp3'), isNull);
      report.pass('M7.3');
    });

    test('M7.4 covering parent and normalized keys are kept', () async {
      final parent = _tempDir('dacx-a9-parent-');
      final child = Directory('${parent.path}${Platform.pathSeparator}shots')
        ..createSync();
      final env = await _make();
      final s = env.settings;
      s.screenshotDir = child.path;
      s.setFileBookmark(parent.path, 'parent-bm');

      s.addRecentFile('/music/a.mp3');
      expect(s.fileBookmark(parent.path), 'parent-bm');
      expect(s.coveringBookmarkKey(child.path), parent.path);
      s.clearRecentFiles();
      expect(s.fileBookmark(parent.path), 'parent-bm');

      final slashKey = '${child.path.replaceAll('\\', '/')}/';
      s.setFileBookmark(slashKey, 'slash-bm');
      s.addRecentFile('/music/b.mp3');
      expect(s.fileBookmark(slashKey), 'slash-bm');
      s.clearRecentFiles();
      expect(s.fileBookmark(slashKey), 'slash-bm');
      report.pass('M7.4');
    });

    test('M7.5 changed or cleared folder releases the old key', () async {
      final a = _tempDir('dacx-a9-shot-a-');
      final b = _tempDir('dacx-a9-shot-b-');
      final env = await _make();
      final s = env.settings;
      s.setFileBookmark(a.path, 'a-bm');
      s.screenshotDir = a.path;
      s.addRecentFile('/music/a.mp3');
      expect(s.fileBookmark(a.path), 'a-bm');

      s.setFileBookmark(b.path, 'b-bm');
      s.screenshotDir = b.path;
      s.addRecentFile('/music/b.mp3');
      expect(s.fileBookmark(a.path), isNull);
      expect(s.fileBookmark(b.path), 'b-bm');
      s.clearRecentFiles();
      expect(s.fileBookmark(b.path), 'b-bm');

      s.screenshotDir = null;
      s.addRecentFile('/music/c.mp3');
      expect(s.fileBookmark(b.path), isNull);
      report.pass('M7.5');
    });

    test('M7.6 without a screenshot folder everything is pruned', () async {
      final env = await _make();
      final s = env.settings;
      s.setFileBookmark('/music/a.mp3', 'a-bm');
      s.setFileBookmark('/other/unrelated', 'other-bm');
      s.addRecentFile('/music/a.mp3');
      s.clearRecentFiles();
      expect(s.fileBookmark('/music/a.mp3'), isNull);
      expect(s.fileBookmark('/other/unrelated'), isNull);
      expect(env.store.values.containsKey('file_bookmarks_v1'), isFalse);
      report.pass('M7.6');
    });
  });

  group('finding 13: debounced preference writes', () {
    test('M13.1 volume burst writes once after the debounce', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        var notifications = 0;
        s.addListener(() => notifications++);
        for (var i = 0; i < 50; i++) {
          s.volume = 10.0 + i;
          expect(s.volume, 10.0 + i);
        }
        expect(notifications, 50);
        expect(env.store.writes, isEmpty);
        async.elapse(_justBefore);
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.writes, ['playback_volume']);
        expect(env.store.values['playback_volume'], 59.0);
        async.elapse(const Duration(seconds: 5));
        expect(env.store.count('playback_volume'), 1);
      });
      report.pass('M13.1');
    });

    test('M13.2 eq bands and preset are debounced', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        var notifications = 0;
        s.addListener(() => notifications++);
        for (var i = 1; i <= 20; i++) {
          s.eqBands = List<double>.filled(SettingsService.eqBandCount, i / 4);
          s.eqPreset = i.isEven ? 'rock' : 'custom';
          expect(s.eqBands.first, i / 4);
          expect(s.eqPreset, i.isEven ? 'rock' : 'custom');
        }
        expect(notifications, 40);
        expect(env.store.writes, isEmpty);
        async.elapse(_justBefore);
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.count('eq_bands'), 1);
        expect(env.store.count('eq_preset'), 1);
        expect(env.store.writes, hasLength(2));
        expect(
          jsonDecode(env.store.values['eq_bands']! as String),
          List<double>.filled(SettingsService.eqBandCount, 5.0),
        );
        expect(env.store.values['eq_preset'], 'rock');
      });
      report.pass('M13.2');
    });

    test('M13.3 subtitle appearance is debounced', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        for (var i = 0; i < 10; i++) {
          s.subtitleFontSize = 30 + i;
          s.subtitlePosition = 90 - (i % 3) * 5;
          s.subtitleOutlineSize = 0.5 + i / 4;
        }
        s.subtitleTextColor = '#112233';
        s.subtitleOutlineColor = '#aabbcc';
        expect(s.subtitleFontSize, 39);
        expect(s.subtitlePosition, 90);
        expect(s.subtitleOutlineSize, 2.75);
        expect(s.subtitleTextColor, '#112233');
        expect(s.subtitleOutlineColor, '#AABBCC');
        expect(env.store.writes, isEmpty);
        async.elapse(_justBefore);
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.writes.toSet(), {
          'subtitle_font_size',
          'subtitle_position',
          'subtitle_outline_size',
          'subtitle_text_color',
          'subtitle_outline_color',
        });
        expect(env.store.writes, hasLength(5));
        expect(env.store.values['subtitle_font_size'], 39);
        expect(env.store.values['subtitle_outline_color'], '#AABBCC');
      });
      report.pass('M13.3');
    });

    test('M13.4 window opacity and blur strength are debounced', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        for (var i = 0; i < 30; i++) {
          s.windowOpacity = 0.6 + i / 100;
          s.windowBlurStrength = i / 40;
        }
        expect(s.windowOpacity, closeTo(0.89, 1e-9));
        expect(s.windowBlurStrength, closeTo(0.725, 1e-9));
        expect(env.store.writes, isEmpty);
        async.elapse(_justBefore);
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.writes.toSet(), {
          'window_opacity',
          'window_blur_strength',
        });
        expect(env.store.writes, hasLength(2));
        expect(
          env.store.values['window_opacity'] as double,
          closeTo(0.89, 1e-9),
        );
      });
      report.pass('M13.4');
    });

    test('M13.5 window geometry flushes together once', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        for (var i = 0; i < 10; i++) {
          s.saveWindowSize(Size(900.0 + i, 600.0 + i));
          s.saveWindowPosition(Offset(10.0 + i, 20.0 + i));
        }
        expect(s.windowSize, const Size(909, 609));
        expect(s.windowPosition, const Offset(19, 29));
        expect(env.store.writes, isEmpty);
        async.elapse(_justBefore);
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.writes.toSet(), {
          'window_width',
          'window_height',
          'window_x',
          'window_y',
        });
        expect(env.store.writes, hasLength(4));
        expect(env.store.values['window_width'], 909.0);
        expect(env.store.values['window_y'], 29.0);
        async.elapse(const Duration(seconds: 5));
        expect(env.store.writes, hasLength(4));
      });
      report.pass('M13.5');
    });

    test('M13.6 each change restarts the debounce', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        s.volume = 40;
        async.elapse(const Duration(milliseconds: 500));
        s.volume = 41;
        async.elapse(const Duration(milliseconds: 500));
        expect(env.store.writes, isEmpty);
        async.elapse(const Duration(milliseconds: 299));
        expect(env.store.writes, isEmpty);
        async.elapse(_oneMs);
        async.flushMicrotasks();
        expect(env.store.writes, ['playback_volume']);
        expect(env.store.values['playback_volume'], 41.0);
      });
      report.pass('M13.6');
    });

    test('M13.7 flushPendingWrites writes everything now', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        s.volume = 33;
        s.eqBands = List<double>.filled(SettingsService.eqBandCount, 3);
        s.subtitleFontSize = 50;
        s.windowOpacity = 0.7;
        s.windowBlurStrength = 0.2;
        s.saveWindowSize(const Size(1000, 700));
        s.saveWindowPosition(const Offset(5, 6));
        expect(env.store.writes, isEmpty);
        unawaited(s.flushPendingWrites());
        async.flushMicrotasks();
        expect(env.store.writes.toSet(), {
          'playback_volume',
          'eq_bands',
          'subtitle_font_size',
          'window_opacity',
          'window_blur_strength',
          'window_width',
          'window_height',
          'window_x',
          'window_y',
        });
        final written = env.store.writes.length;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(env.store.writes, hasLength(written));
      });
      final reopened = await _reopen(env.store);
      expect(reopened.volume, 33);
      expect(reopened.eqBands.first, 3);
      expect(reopened.subtitleFontSize, 50);
      expect(reopened.windowSize, const Size(1000, 700));
      expect(reopened.windowPosition, const Offset(5, 6));
      report.pass('M13.7');
    });

    test('M13.8 exit hook and dispose flush pending writes', () async {
      final env = await _make();
      env.settings.volume = 21;
      env.settings.saveWindowSize(const Size(800, 600));
      expect(env.store.writes, isEmpty);
      await AppExitHooks.runAll();
      expect(env.store.values['playback_volume'], 21.0);
      expect(env.store.values['window_width'], 800.0);

      final disposing = await _make(autoDispose: false);
      disposing.settings.eqPreset = 'bass';
      disposing.settings.volume = 12;
      expect(disposing.store.writes, isEmpty);
      disposing.settings.dispose();
      expect(disposing.store.values['eq_preset'], 'bass');
      expect(disposing.store.values['playback_volume'], 12.0);
      report.pass('M13.8');
    });

    test('M13.9 resetAll drops pending writes', () async {
      final env = await _make();
      env.settings.volume = 40;
      env.settings.eqBands = List<double>.filled(
        SettingsService.eqBandCount,
        4,
      );
      await env.settings.resetAll();
      expect(env.settings.volume, 100.0);
      expect(env.settings.eqBands.first, 0);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(env.store.values.containsKey('playback_volume'), isFalse);
      expect(env.store.values.containsKey('eq_bands'), isFalse);
      expect(env.settings.volume, 100.0);
      report.pass('M13.9');
    });
  });

  group('finding 14: setter equality short-circuit', () {
    final selfAssign = <String, void Function(SettingsService)>{
      'advancedPlaybackToolsEnabled': (s) =>
          s.advancedPlaybackToolsEnabled = s.advancedPlaybackToolsEnabled,
      'autoPlay': (s) => s.autoPlay = s.autoPlay,
      'alwaysOnTop': (s) => s.alwaysOnTop = s.alwaysOnTop,
      'minimizeToTray': (s) => s.minimizeToTray = s.minimizeToTray,
      'rememberWindow': (s) => s.rememberWindow = s.rememberWindow,
      'updateCheckEnabled': (s) => s.updateCheckEnabled = s.updateCheckEnabled,
      'windowBlurEnabled': (s) => s.windowBlurEnabled = s.windowBlurEnabled,
      'experimentalFeaturesEnabled': (s) =>
          s.experimentalFeaturesEnabled = s.experimentalFeaturesEnabled,
      'linuxCompositorBlurExperimental': (s) =>
          s.linuxCompositorBlurExperimental = s.linuxCompositorBlurExperimental,
      'debugModeEnabled': (s) => s.debugModeEnabled = s.debugModeEnabled,
      'eqEnabled': (s) => s.eqEnabled = s.eqEnabled,
      'osdEnabled': (s) => s.osdEnabled = s.osdEnabled,
      'seekPreviewEnabled': (s) => s.seekPreviewEnabled = s.seekPreviewEnabled,
      'mediaSessionEnabled': (s) =>
          s.mediaSessionEnabled = s.mediaSessionEnabled,
      'resumePlaybackEnabled': (s) =>
          s.resumePlaybackEnabled = s.resumePlaybackEnabled,
      'playlistShuffle': (s) => s.playlistShuffle = s.playlistShuffle,
      'emptyStateTipDismissed': (s) =>
          s.emptyStateTipDismissed = s.emptyStateTipDismissed,
      'allowMultipleInstances': (s) =>
          s.allowMultipleInstances = s.allowMultipleInstances,
      'windowMaximized': (s) => s.windowMaximized = s.windowMaximized,
      'hwDec': (s) => s.hwDec = s.hwDec,
      'themeMode': (s) => s.themeMode = s.themeMode,
      'accentColor': (s) => s.accentColor = s.accentColor,
      'loopMode': (s) => s.loopMode = s.loopMode,
      'updateChannel': (s) => s.updateChannel = s.updateChannel,
      'screenshotFormat': (s) => s.screenshotFormat = s.screenshotFormat,
      'speed': (s) => s.speed = s.speed,
      'volume': (s) => s.volume = s.volume,
      'windowOpacity': (s) => s.windowOpacity = s.windowOpacity,
      'windowBlurStrength': (s) => s.windowBlurStrength = s.windowBlurStrength,
      'subtitleFontSize': (s) => s.subtitleFontSize = s.subtitleFontSize,
      'subtitlePosition': (s) => s.subtitlePosition = s.subtitlePosition,
      'subtitleTextColor': (s) => s.subtitleTextColor = s.subtitleTextColor,
      'subtitleOutlineColor': (s) =>
          s.subtitleOutlineColor = s.subtitleOutlineColor,
      'eqPreset': (s) => s.eqPreset = s.eqPreset,
      'eqBands': (s) => s.eqBands = s.eqBands,
      'keybinds': (s) => s.keybinds = s.keybinds,
      'lastUpdateCheck': (s) => s.lastUpdateCheck = s.lastUpdateCheck,
    };

    final seeded = <String, Object>{
      'playback_auto_play': false,
      'appearance_theme': 'light',
      'appearance_accent': 'teal',
      'playback_loop_mode': 'loop',
      'system_hwdec': 'no',
      'playback_volume': 55.0,
      'playback_speed': 1.5,
      'window_opacity': 0.8,
      'window_blur_strength': 0.3,
      'subtitle_font_size': 44,
      'subtitle_position': 90,
      'subtitle_outline_size': 2.0,
      'subtitle_text_color': '#112233FF',
      'subtitle_outline_color': '#445566FF',
      'eq_preset': 'rock',
      'eq_bands': '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0]',
      'keybinds_v1': '{"play_pause":["Space","K"]}',
      'window_maximized': true,
      'update_last_check': 1700000000000,
      'screenshot_format': 'jpg',
      'allow_multiple_instances': true,
    };

    test('M14.1 equal values do not write or notify', () async {
      for (final seed in [const <String, Object>{}, seeded]) {
        final env = await _make(seed: seed);
        final s = env.settings;
        fakeAsync((async) {
          var notifications = 0;
          s.addListener(() => notifications++);
          selfAssign.forEach((name, assign) {
            assign(s);
            expect(notifications, 0, reason: '$name notified');
            expect(env.store.writes, isEmpty, reason: '$name wrote');
          });
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(env.store.writes, isEmpty);
        });
      }
      report.pass('M14.1');
    });

    test(
      'M14.2 clamped and rounded values compare after normalization',
      () async {
        final env = await _make(
          seed: {'subtitle_outline_size': 2.0, 'subtitle_position': 90},
        );
        final s = env.settings;
        fakeAsync((async) {
          var notifications = 0;
          s.addListener(() => notifications++);

          s.volume = 150;
          s.volume = 100;
          s.subtitlePosition = 88;
          s.subtitlePosition = 91;
          s.subtitleOutlineSize = 2.1;
          s.subtitleTextColor = 'not-a-color';
          s.speed = 1.0;
          expect(notifications, 0);
          expect(env.store.writes, isEmpty);

          s.windowOpacity = 0.1;
          expect(notifications, 1);
          s.windowOpacity = 0.2;
          expect(notifications, 1);
          s.windowBlurStrength = 2.0;
          expect(notifications, 2);
          s.windowBlurStrength = 3.0;
          expect(notifications, 2);
          s.subtitleFontSize = 100;
          expect(notifications, 3);
          s.subtitleFontSize = 80;
          expect(notifications, 3);
          s.subtitleTextColor = '#abcdef';
          expect(notifications, 4);
          s.subtitleTextColor = '#ABCDEF';
          expect(notifications, 4);
          s.speed = 9.0;
          expect(notifications, 5);
          s.speed = 8.0;
          expect(notifications, 5);
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(env.store.count('window_opacity'), 1);
          expect(env.store.count('window_blur_strength'), 1);
          expect(env.store.count('subtitle_font_size'), 1);
          expect(env.store.count('subtitle_text_color'), 1);
          expect(env.store.count('playback_speed'), 1);
        });
        report.pass('M14.2');
      },
    );

    test('M14.3 lists and maps use deep equality', () async {
      final env = await _make();
      final s = env.settings;
      fakeAsync((async) {
        var notifications = 0;
        s.addListener(() => notifications++);

        s.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        expect(notifications, 1);
        s.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        s.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        s.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0];
        expect(notifications, 1);
        s.eqBands = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11];
        expect(notifications, 2);

        s.keybinds = {
          'play_pause': ['Space', 'K'],
        };
        expect(notifications, 3);
        s.keybinds = {
          'play_pause': ['Space', 'K'],
        };
        expect(notifications, 3);
        expect(env.store.count('keybinds_v1'), 1);
        s.keybinds = {
          'play_pause': ['Space'],
        };
        expect(notifications, 4);
        expect(env.store.count('keybinds_v1'), 2);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(env.store.count('eq_bands'), 1);
      });
      report.pass('M14.3');
    });

    test('M14.4 recents, keybind reset, geometry and bookmarks', () async {
      final env = await _make();
      final s = env.settings;
      final dir = _tempDir('dacx-a9-eq-');
      s.addRecentFile('/music/a.mp3');
      s.setFileBookmark('/music/a.mp3', 'a-bm');
      s.lastOpenDirectory = dir.path;
      s.screenshotDir = dir.path;
      s.saveWindowSize(const Size(900, 600));
      s.saveWindowPosition(const Offset(1, 2));
      await s.flushPendingWrites();
      env.store.writes.clear();
      var notifications = 0;
      s.addListener(() => notifications++);

      s.addRecentFile('/music/a.mp3');
      s.setFileBookmark('/music/a.mp3', 'a-bm');
      s.lastOpenDirectory = dir.path;
      s.screenshotDir = dir.path;
      s.saveWindowSize(const Size(900, 600));
      s.saveWindowPosition(const Offset(1, 2));
      s.resetKeybinds();

      expect(notifications, 0);
      expect(env.store.writes, isEmpty);
      s.clearRecentFiles();
      expect(notifications, 1);
      env.store.writes.clear();
      s.clearRecentFiles();
      expect(notifications, 1);
      expect(env.store.writes, isEmpty);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(env.store.writes, isEmpty);
      });
      report.pass('M14.4');
    });

    test('M14.5 a changed value still writes and notifies once', () async {
      final env = await _make();
      final s = env.settings;
      var notifications = 0;
      s.addListener(() => notifications++);

      s.autoPlay = false;
      expect(notifications, 1);
      expect(env.store.writes, ['playback_auto_play']);
      s.themeMode = ThemeMode.light;
      expect(notifications, 2);
      s.accentColor = AccentColor.pink;
      expect(notifications, 3);
      s.loopMode = LoopMode.single;
      expect(notifications, 4);
      s.hwDec = 'no';
      expect(notifications, 5);
      s.alwaysOnTop = true;
      expect(notifications, 6);
      s.screenshotFormat = 'jpg';
      expect(notifications, 7);
      expect(env.store.writes, hasLength(7));
      report.pass('M14.5');
    });
  });

  group('finding 15: no sync filesystem calls in settings', () {
    test('M15.1 lastOpenDirectory does not touch the filesystem', () async {
      final env = await _make();
      final s = env.settings;
      final touched = <String>[];
      IOOverrides.runZoned(
        () {
          s.lastOpenDirectory = '/definitely/missing/a9-last-dir';
          expect(s.lastOpenDirectory, '/definitely/missing/a9-last-dir');
          for (final bad in ['../escape', 'a/../b', r'C:\a\..\b', 'x\u0000y']) {
            s.lastOpenDirectory = bad;
            expect(s.lastOpenDirectory, isNull, reason: bad);
          }
          s.lastOpenDirectory = '/definitely/missing/a9-last-dir';
          s.lastOpenDirectory = null;
          expect(s.lastOpenDirectory, isNull);
        },
        createDirectory: (path) {
          touched.add(path);
          throw StateError('sync filesystem call on the UI isolate');
        },
      );
      expect(touched, isEmpty);
      report.pass('M15.1');
    });

    test('M15.2 screenshotDir does not touch the filesystem', () async {
      final env = await _make(
        seed: {'screenshot_dir': '/definitely/missing/a9-seeded'},
      );
      final s = env.settings;
      final touched = <String>[];
      IOOverrides.runZoned(
        () {
          expect(s.screenshotDir, '/definitely/missing/a9-seeded');
          s.screenshotDir = '/definitely/missing/a9-shots';
          expect(s.screenshotDir, '/definitely/missing/a9-shots');
          for (final bad in ['../escape', 'a/../b', r'C:\a\..\b', 'x\u0000y']) {
            s.screenshotDir = bad;
            expect(s.screenshotDir, isNull, reason: bad);
          }
          s.screenshotDir = '/definitely/missing/a9-shots';
          s.screenshotDir = null;
          expect(s.screenshotDir, isNull);
        },
        createDirectory: (path) {
          touched.add(path);
          throw StateError('sync filesystem call on the UI isolate');
        },
      );
      expect(touched, isEmpty);
      report.pass('M15.2');
    });
  });

  group('finding 31: dead members', () {
    test('M31.1 AccentColor no longer declares a label', () {
      final source = File('lib/services/settings_service.dart')
          .readAsStringSync();
      final match = RegExp(r'enum AccentColor \{([\s\S]*?)\n\}')
          .firstMatch(source);
      expect(match, isNotNull);
      expect(match!.group(1), isNot(contains('label')));
      expect(match.group(1), isNot(contains("'Blue Grey'")));
      report.pass('M31.1');
    });

    test('M31.2 accent identity and colors are unchanged', () async {
      expect(AccentColor.values.map((a) => a.name), [
        'blueGrey',
        'blue',
        'teal',
        'purple',
        'red',
        'orange',
        'green',
        'pink',
      ]);
      expect(AccentColor.blueGrey.color, Colors.blueGrey);
      expect(AccentColor.pink.color, Colors.pink);
      for (final accent in AccentColor.values) {
        final env = await _make(seed: {'appearance_accent': accent.name});
        expect(env.settings.accentColor, accent);
      }
      final env = await _make();
      env.settings.accentColor = AccentColor.orange;
      expect(env.store.values['appearance_accent'], 'orange');
      report.pass('M31.2');
    });
  });
}
