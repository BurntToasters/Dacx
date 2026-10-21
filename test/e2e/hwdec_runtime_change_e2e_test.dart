// Acceptance coverage for runtime hwdec changes.
// See HWDEC_RUNTIME_CHANGE_FAILURE_MODES.md for the failure inventory.
// The headless surface means no real VideoController exists here; that the
// surface is not rebuilt on change is proven by code review of _applyHwDec.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';

import '../support/player_screen_harness.dart';

List<String> _hwdecValues(HeadlessPlayerService player) => [
  for (final call in player.propertyCalls)
    if (call.name == 'hwdec') call.value,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  Future<({HeadlessPlayerService player, SettingsService settings})> pumpScreen(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    String? initialFile,
  }) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(prefs: prefs);
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialFile: initialFile,
      ),
    );
    await tester.pumpAndSettle();
    return (player: player, settings: services.settings);
  }

  testWidgets('startup applies the saved hwdec value once', (tester) async {
    final screen = await pumpScreen(
      tester,
      prefs: const {'system_hwdec': 'no'},
    );
    expect(_hwdecValues(screen.player), ['no']);
    await tester.pumpWidget(const SizedBox.shrink());
    screen.settings.dispose();
  });

  testWidgets(
    'runtime hwdec change reaches mpv without interrupting playback',
    (tester) async {
      final file = p.normalize(p.absolute('e2e/hwdec.mp3'));
      final screen = await pumpScreen(tester, initialFile: file);
      final player = screen.player;
      final playing = <bool>[];
      final playingSub = player.playingStream.listen(playing.add);
      addTearDown(playingSub.cancel);
      player.emitPosition(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      final openCount = player.openCalls.length;

      screen.settings.hwDec = 'no';
      await tester.pumpAndSettle();

      expect(_hwdecValues(player), ['auto', 'no']);
      expect(player.openCalls.length, openCount);
      expect(player.openCalls.single.path, file);
      expect(playing, isNot(contains(false)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      screen.settings.dispose();
    },
  );

  testWidgets('repeated toggles write one property per real change', (
    tester,
  ) async {
    final screen = await pumpScreen(tester, initialFile: '/e2e/toggle.mp3');
    for (final value in ['no', 'auto', 'no', 'auto']) {
      screen.settings.hwDec = value;
      await tester.pumpAndSettle();
    }
    // Re-setting the current value must not re-apply it to mpv.
    screen.settings.hwDec = 'auto';
    await tester.pumpAndSettle();

    expect(_hwdecValues(screen.player), ['auto', 'no', 'auto', 'no', 'auto']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    screen.settings.dispose();
  });

  testWidgets('failed hwdec write surfaces no unhandled error', (tester) async {
    final file = p.normalize(p.absolute('e2e/fail.mp3'));
    final screen = await pumpScreen(tester, initialFile: file);
    screen.player.failProperties(['hwdec']);
    screen.settings.hwDec = 'no';
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(_hwdecValues(screen.player), ['auto', 'no']);
    expect(screen.player.openCalls.single.path, file);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    screen.settings.dispose();
  });
}
