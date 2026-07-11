import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/playback/player_ui_policies.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/transport_controls.dart';

import '../support/player_screen_harness.dart';

/// Widget-level checks for player UI gating without libmpv.
///
/// Full [PlayerScreen] pump tests belong in integration/build environments
/// where native media_kit libraries are available (see `npm run check:build-smoke`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  Future<SettingsService> settingsWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    return SettingsService(shared);
  }

  Widget wrapTransport({
    required SettingsService settings,
    required VoidCallback? onOpenUrl,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        body: TransportControls(
          isPlaying: false,
          volume: 100,
          hasMedia: false,
          speed: 1,
          loopMode: LoopMode.none,
          recentFiles: const [],
          onPlayPause: () {},
          onStop: () {},
          onOpenFile: () {},
          onReopenLast: () {},
          onVolumeChanged: (_) {},
          onLoopModeChanged: (_) {},
          onRecentFileSelected: (_) {},
          onSettingsPressed: () {},
          onOpenUrl: onOpenUrl,
        ),
      ),
    );
  }

  group('PlayerScreen experimental UI gating', () {
    testWidgets('shows Open URL when experimental features are disabled', (
      tester,
    ) async {
      final settings = await settingsWith({
        'experimental_features_enabled': false,
      });
      final showUrl = PlayerUiPolicies.showOpenUrlButton(settings);

      await tester.pumpWidget(
        wrapTransport(settings: settings, onOpenUrl: showUrl ? () {} : null),
      );
      await tester.pumpAndSettle();

      expect(showUrl, isTrue);
      expect(find.byTooltip('Open URL'), findsOneWidget);
    });

    testWidgets('shows Open URL when experimental features are enabled', (
      tester,
    ) async {
      final settings = await settingsWith({
        'experimental_features_enabled': true,
      });
      final showUrl = PlayerUiPolicies.showOpenUrlButton(settings);

      await tester.pumpWidget(
        wrapTransport(settings: settings, onOpenUrl: showUrl ? () {} : null),
      );
      await tester.pumpAndSettle();

      expect(showUrl, isTrue);
      expect(find.byTooltip('Open URL'), findsOneWidget);
    });

    test('accepts injected IPlayerService reference', () async {
      final fake = HeadlessPlayerService();
      final settings = await settingsWith({});
      final screen = PlayerScreen(
        settings: settings,
        debugLog: DebugLogService(isEnabled: () => false),
        updateService: UpdateService(
          debugLog: DebugLogService(isEnabled: () => false),
          debugSource: 'harness',
        ),
        playerService: fake,
      );
      expect(screen.playerService, same(fake));
    });
  });
}
