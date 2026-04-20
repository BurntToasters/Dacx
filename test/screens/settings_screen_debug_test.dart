import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
