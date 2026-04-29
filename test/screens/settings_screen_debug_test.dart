import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/theme/window_visuals.dart';

Future<({SettingsService settings, DebugLogService debugLog})> _buildServices({
  required bool debugEnabled,
}) async {
  SharedPreferences.setMockInitialValues({'debug_mode_enabled': debugEnabled});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);
  return (settings: settings, debugLog: debugLog);
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
    ],
  );
}

class _FakeUrlLauncherPlatform extends UrlLauncherPlatform {
  _FakeUrlLauncherPlatform({this.canLaunchResult = true});

  final bool canLaunchResult;
  final List<String> canLaunchCalls = <String>[];
  final List<({String url, LaunchOptions options})> launchUrlCalls =
      <({String url, LaunchOptions options})>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
    return canLaunchResult;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchUrlCalls.add((url: url, options: options));
    return true;
  }
}

void main() {
  group('SettingsScreen debug log panel', () {
    testWidgets('is hidden when debug mode is disabled', (tester) async {
      final services = await _buildServices(debugEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Debug Log'), findsNothing);
    });

    testWidgets('appears when debug mode is enabled', (tester) async {
      final services = await _buildServices(debugEnabled: true);
      services.debugLog.log(category: DebugLogCategory.system, event: 'boot');

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Debug Log'), 300);
      await tester.pumpAndSettle();

      expect(find.text('Debug Log'), findsOneWidget);
      expect(services.debugLog.entryCount, greaterThan(0));
      expect(
        find.textContaining('${services.debugLog.entryCount} entries'),
        findsOneWidget,
      );
    });

    testWidgets('clear log button removes entries and updates count', (
      tester,
    ) async {
      final services = await _buildServices(debugEnabled: true);
      services.debugLog.log(category: DebugLogCategory.ui, event: 'tap_1');
      services.debugLog.log(category: DebugLogCategory.ui, event: 'tap_2');

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Debug Log'), 300);
      await tester.pumpAndSettle();

      expect(services.debugLog.entryCount, greaterThan(1));
      expect(
        find.textContaining('${services.debugLog.entryCount} entries'),
        findsOneWidget,
      );

      await tester.tap(find.text('Clear Log'));
      await tester.pumpAndSettle();

      expect(find.textContaining('0 entries'), findsOneWidget);
      expect(find.text('No debug events yet.'), findsOneWidget);
    });
  });

  group('SettingsScreen external links', () {
    late UrlLauncherPlatform originalLauncher;

    setUp(() {
      originalLauncher = UrlLauncherPlatform.instance;
    });

    tearDown(() {
      UrlLauncherPlatform.instance = originalLauncher;
    });

    testWidgets('renders FAQ and support actions in General section', (
      tester,
    ) async {
      final services = await _buildServices(debugEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Help'), 300);
      await tester.pumpAndSettle();

      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Support this project'), findsOneWidget);
    });

    testWidgets('FAQ action launches expected URL externally', (tester) async {
      final services = await _buildServices(debugEnabled: false);
      final launcher = _FakeUrlLauncherPlatform();
      UrlLauncherPlatform.instance = launcher;

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Help'), 300);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();

      expect(
        launcher.canLaunchCalls,
        contains('https://help.rosie.run/dacx/en-us/faq'),
      );
      expect(launcher.launchUrlCalls.length, 1);
      expect(
        launcher.launchUrlCalls.single.url,
        'https://help.rosie.run/dacx/en-us/faq',
      );
      expect(
        launcher.launchUrlCalls.single.options.mode,
        PreferredLaunchMode.externalApplication,
      );
    });

    testWidgets('support action launches expected URL externally', (
      tester,
    ) async {
      final services = await _buildServices(debugEnabled: false);
      final launcher = _FakeUrlLauncherPlatform();
      UrlLauncherPlatform.instance = launcher;

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Support this project'), 300);
      await tester.tap(find.text('Support this project'));
      await tester.pumpAndSettle();

      expect(launcher.canLaunchCalls, contains('https://rosie.run/support'));
      expect(launcher.launchUrlCalls.length, 1);
      expect(launcher.launchUrlCalls.single.url, 'https://rosie.run/support');
      expect(
        launcher.launchUrlCalls.single.options.mode,
        PreferredLaunchMode.externalApplication,
      );
    });

    testWidgets('FAQ action does not crash when launcher returns false', (
      tester,
    ) async {
      final services = await _buildServices(debugEnabled: false);
      final launcher = _FakeUrlLauncherPlatform(canLaunchResult: false);
      UrlLauncherPlatform.instance = launcher;

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: SettingsScreen(
            settings: services.settings,
            debugLog: services.debugLog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Help'), 300);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();

      expect(
        launcher.canLaunchCalls,
        contains('https://help.rosie.run/dacx/en-us/faq'),
      );
      expect(launcher.launchUrlCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
