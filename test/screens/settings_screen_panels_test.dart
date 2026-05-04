import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/theme/window_visuals.dart';

Future<({SettingsService settings, DebugLogService debugLog})> _services({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);
  return (settings: settings, debugLog: debugLog);
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
    ],
  );
}

Widget _wrap(SettingsService s, DebugLogService log) => MaterialApp(
  theme: _theme(),
  home: SettingsScreen(settings: s, debugLog: log),
);

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300);
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen toggles', () {
    testWidgets('Auto-play switch flips the persisted setting', (tester) async {
      final svc = await _services();
      expect(svc.settings.autoPlay, isTrue);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Auto-play on file open'));
      await tester.tap(find.text('Auto-play on file open'));
      await tester.pumpAndSettle();
      expect(svc.settings.autoPlay, isFalse);
    });

    testWidgets('Resume from last position toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.resumePlaybackEnabled;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Resume from last position'));
      await tester.tap(find.text('Resume from last position'));
      await tester.pumpAndSettle();
      expect(svc.settings.resumePlaybackEnabled, !before);
    });

    testWidgets('On-screen display toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.osdEnabled;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('On-screen display'));
      await tester.tap(find.text('On-screen display'));
      await tester.pumpAndSettle();
      expect(svc.settings.osdEnabled, !before);
    });

    testWidgets('System media keys / Now Playing toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.mediaSessionEnabled;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('System media keys / Now Playing'));
      await tester.tap(find.text('System media keys / Now Playing'));
      await tester.pumpAndSettle();
      expect(svc.settings.mediaSessionEnabled, !before);
    });

    testWidgets('Always on top toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.alwaysOnTop;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Always on top'));
      await tester.tap(find.text('Always on top'));
      await tester.pumpAndSettle();
      expect(svc.settings.alwaysOnTop, !before);
    });

    testWidgets('Remember window toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.rememberWindow;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Remember window size & position'));
      await tester.tap(find.text('Remember window size & position'));
      await tester.pumpAndSettle();
      expect(svc.settings.rememberWindow, !before);
    });

    testWidgets('Check for updates on launch toggles', (tester) async {
      final svc = await _services();
      final before = svc.settings.updateCheckEnabled;
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('Check for updates on launch'));
      await tester.tap(find.text('Check for updates on launch'));
      await tester.pumpAndSettle();
      expect(svc.settings.updateCheckEnabled, !before);
    });
  });

  group('SettingsScreen sections', () {
    testWidgets('shows Playback, Appearance, General, Experimental headers', (
      tester,
    ) async {
      final svc = await _services();
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      for (final label in [
        'Playback',
        'Appearance',
        'General',
        'Experimental',
      ]) {
        await _scrollTo(tester, find.text(label));
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('experimental panels are hidden until enabled', (tester) async {
      final svc = await _services();
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      // Window opacity is part of the experimental cluster.
      expect(find.text('Window opacity'), findsNothing);
    });

    testWidgets('experimental panels appear after toggling experiments on', (
      tester,
    ) async {
      final svc = await _services(
        initial: const {'experimental_features_enabled': true},
      );
      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();
      // Reveal experimental controls.
      await _scrollTo(tester, find.text('Window opacity'));
      expect(find.text('Window opacity'), findsOneWidget);
    });
  });
}
