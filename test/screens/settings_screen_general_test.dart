import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
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

Widget _wrap(SettingsService s, DebugLogService log) {
  final updates = UpdateService(debugLog: log, debugSource: 'settings_test');
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: _theme(),
    home: SettingsScreen(settings: s, debugLog: log, updateService: updates),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300);
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen general panel', () {
    testWidgets('Allow multiple windows toggles persisted setting', (
      tester,
    ) async {
      final svc = await _services();
      expect(svc.settings.allowMultipleInstances, isFalse);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Allow multiple windows'));
      await tester.tap(find.text('Allow multiple windows'));
      await tester.pumpAndSettle();

      expect(svc.settings.allowMultipleInstances, isTrue);
    });

    testWidgets('Loop mode segmented button persists selection', (
      tester,
    ) async {
      final svc = await _services();
      expect(svc.settings.loopMode, LoopMode.none);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text(LoopMode.single.label));
      await tester.tap(find.text(LoopMode.single.label));
      await tester.pumpAndSettle();

      expect(svc.settings.loopMode, LoopMode.single);

      await tester.tap(find.text(LoopMode.loop.label));
      await tester.pumpAndSettle();
      expect(svc.settings.loopMode, LoopMode.loop);
    });

    testWidgets('Theme mode buttons persist selection', (tester) async {
      final svc = await _services();
      expect(svc.settings.themeMode, ThemeMode.dark);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Light'));
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(svc.settings.themeMode, ThemeMode.light);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(svc.settings.themeMode, ThemeMode.system);
    });

    testWidgets('Update channel defaults to auto and switches to beta', (
      tester,
    ) async {
      final svc = await _services();
      expect(svc.settings.updateChannel, UpdateChannel.auto);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Beta'));
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(svc.settings.updateChannel, UpdateChannel.beta);

      await tester.tap(find.text('Stable'));
      await tester.pumpAndSettle();
      expect(svc.settings.updateChannel, UpdateChannel.stable);
    });

    testWidgets('Accent color selection persists', (tester) async {
      final svc = await _services();
      expect(svc.settings.accentColor, AccentColor.blueGrey);

      await tester.pumpWidget(_wrap(svc.settings, svc.debugLog));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.bySemanticsLabel('Accent color Teal'));
      await tester.tap(find.bySemanticsLabel('Accent color Teal'));
      await tester.pumpAndSettle();

      expect(svc.settings.accentColor, AccentColor.teal);
    });
  });
}
