import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/playback/advanced_playback_models.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/theme/window_visual_inputs.dart';

/// Mirrors the settings listener in the app shell against real settings.
class _Gate {
  _Gate(this.settings)
    : _visuals = WindowVisualInputs.fromSettings(settings),
      _tray = settings.minimizeToTray {
    settings.addListener(_onChange);
  }

  final SettingsService settings;
  WindowVisualInputs _visuals;
  bool _tray;
  int visualApplies = 0;
  int trayApplies = 0;

  void _onChange() {
    final visuals = WindowVisualInputs.fromSettings(settings);
    if (visuals != _visuals) {
      _visuals = visuals;
      visualApplies++;
    }
    final tray = settings.minimizeToTray;
    if (tray != _tray) {
      _tray = tray;
      trayApplies++;
    }
  }

  void dispose() => settings.removeListener(_onChange);
}

void main() {
  late SettingsService settings;
  late _Gate gate;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    gate = _Gate(settings);
  });

  tearDown(() => gate.dispose());

  void expectCounts({required int visual, required int tray}) {
    expect(gate.visualApplies, visual, reason: 'visual applies');
    expect(gate.trayApplies, tray, reason: 'tray applies');
  }

  test('volume, speed, loop, recents, EQ, markers do not count', () async {
    settings.volume = 0.2;
    settings.speed = 1.5;
    settings.loopMode = LoopMode.loop;
    settings.addRecentFile('/music/a.mp3');
    settings.eqEnabled = true;
    settings.eqBands = List<double>.filled(10, 2.0);
    settings.addPlaybackMarker(
      '/music/a.mp3',
      const PlaybackMarker(id: 'm1', positionMs: 1000, label: 'one'),
    );
    expectCounts(visual: 0, tray: 0);
  });

  test('each visual input counts as a visual change', () async {
    settings.themeMode = ThemeMode.light;
    expectCounts(visual: 1, tray: 0);

    settings.windowBlurEnabled = true;
    expectCounts(visual: 2, tray: 0);

    settings.windowBlurStrength = 0.9;
    expectCounts(visual: 3, tray: 0);

    settings.windowOpacity = 0.8;
    expectCounts(visual: 4, tray: 0);

    settings.experimentalFeaturesEnabled = true;
    expectCounts(visual: 5, tray: 0);

    settings.linuxCompositorBlurExperimental = true;
    expectCounts(visual: 6, tray: 0);
  });

  test('minimize-to-tray counts for tray only', () async {
    settings.minimizeToTray = true;
    expectCounts(visual: 0, tray: 1);

    settings.minimizeToTray = false;
    expectCounts(visual: 0, tray: 2);
  });

  test(
    'reset after non-default visual settings counts and restores defaults',
    () async {
      settings.themeMode = ThemeMode.light;
      settings.windowBlurEnabled = true;
      settings.windowOpacity = 0.7;
      settings.minimizeToTray = true;
      expectCounts(visual: 3, tray: 1);

      await settings.resetAll();
      expectCounts(visual: 4, tray: 2);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.windowBlurEnabled, isFalse);
      expect(settings.windowOpacity, 1.0);
    },
  );

  test('reset while visuals are already default does not count', () async {
    await settings.resetAll();
    expectCounts(visual: 0, tray: 0);
  });

  test('repeated notifications with no change do not count', () async {
    settings.windowOpacity = 1.0;
    settings.windowBlurEnabled = false;
    settings.minimizeToTray = false;
    settings.windowOpacity = settings.windowOpacity;
    settings.windowBlurEnabled = settings.windowBlurEnabled;
    settings.minimizeToTray = settings.minimizeToTray;
    expectCounts(visual: 0, tray: 0);
  });

  test('out-of-range values clamped to stored value do not count', () async {
    settings.windowOpacity = 0.1;
    expectCounts(visual: 1, tray: 0);
    expect(
      settings.windowOpacity,
      WindowVisualInputs.fromSettings(settings).opacity,
    );

    settings.windowOpacity = 0.55;
    expectCounts(visual: 1, tray: 0);
  });

  test('A -> B -> A counts on each step', () async {
    settings.windowOpacity = 0.8;
    settings.windowOpacity = 1.0;
    expectCounts(visual: 2, tray: 0);
  });

  test('snapshot does not change when settings later change', () async {
    final before = WindowVisualInputs.fromSettings(settings);
    settings.windowBlurStrength = 0.9;
    expect(before.blurStrength, isNot(0.9));
    expect(WindowVisualInputs.fromSettings(settings).blurStrength, 0.9);
  });

  test(
    'equal state gives equal snapshots, any one-field diff is unequal',
    () async {
      final a = WindowVisualInputs.fromSettings(settings);
      final b = WindowVisualInputs.fromSettings(settings);
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      settings.windowBlurStrength = 0.56;
      expect(WindowVisualInputs.fromSettings(settings), isNot(a));
    },
  );

  test('visual change before gate creation is not treated as new', () async {
    gate.dispose();
    settings.themeMode = ThemeMode.light;
    gate = _Gate(settings);
    settings.volume = 0.3;
    expectCounts(visual: 0, tray: 0);
  });
}
