import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/instance_mode_service.dart';

import '../support/player_screen_harness.dart';

class _GatedPlayer extends HeadlessPlayerService {
  Completer<void>? holdNextDelay;
  final volumes = <double>[];

  @override
  Future<bool> setProperty(String name, String value) async {
    if (name == 'audio-delay' && holdNextDelay != null) {
      final gate = holdNextDelay!;
      holdNextDelay = null;
      await gate.future;
    }
    return super.setProperty(name, value);
  }

  @override
  Future<void> setVolume(double value) async {
    volumes.add(value);
    await super.setVolume(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  test('pending delay persists only against its own source', () async {
    final services = await PlayerScreenHarness.createServices();
    services.settings.advancedPlaybackToolsEnabled = true;
    final player = _GatedPlayer();
    final controller = AdvancedPlaybackController(
      settings: services.settings,
      player: player,
    );
    await controller.setSource(PlayableSource.file('/audit/a.mp3'));
    final gate = Completer<void>();
    player.holdNextDelay = gate;
    final changing = controller.adjustAudioDelay(100);
    await controller.setSource(PlayableSource.file('/audit/b.mp3'));
    gate.complete();
    await changing;
    expect(services.settings.playbackAdjustmentFor('/audit/b.mp3').audioMs, 0);
    controller.dispose();
    services.settings.dispose();
    await player.dispose();
  });

  test('pending delay survives Stop clearing the source', () async {
    final services = await PlayerScreenHarness.createServices();
    services.settings.advancedPlaybackToolsEnabled = true;
    final player = _GatedPlayer();
    final controller = AdvancedPlaybackController(
      settings: services.settings,
      player: player,
    );
    await controller.setSource(PlayableSource.file('/audit/a.mp3'));
    final gate = Completer<void>();
    player.holdNextDelay = gate;
    final changing = controller.adjustAudioDelay(100);
    await controller.setSource(null);
    gate.complete();
    await changing;
    controller.dispose();
    services.settings.dispose();
    await player.dispose();
  });

  test('concurrent delay adjustments accumulate', () async {
    final services = await PlayerScreenHarness.createServices();
    services.settings.advancedPlaybackToolsEnabled = true;
    final player = _GatedPlayer();
    final controller = AdvancedPlaybackController(
      settings: services.settings,
      player: player,
    );
    await controller.setSource(PlayableSource.file('/audit/a.mp3'));
    final gate = Completer<void>();
    player.holdNextDelay = gate;
    final first = controller.adjustAudioDelay(100);
    final second = controller.adjustAudioDelay(100);
    gate.complete();
    await Future.wait([first, second]);
    expect(
      services.settings.playbackAdjustmentFor('/audit/a.mp3').audioMs,
      200,
    );
    controller.dispose();
    services.settings.dispose();
    await player.dispose();
  });

  testWidgets('paused dialog drops cleared A-B range', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    services.settings.advancedPlaybackToolsEnabled = true;
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/audit/loop.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    player.emitDuration(const Duration(minutes: 2));
    player.emitPosition(const Duration(seconds: 10));
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('advanced-playback-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('advanced-set-a')));
    await tester.pumpAndSettle();
    player.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('advanced-set-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('advanced-clear-loop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('advanced-clear-loop')), findsNothing);
    expect(find.byKey(const ValueKey('advanced-set-a')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    services.settings.dispose();
  });

  testWidgets('reset applies default volume to the live player', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final directory = Directory.systemTemp.createTempSync('dacx-reset-');
    InstanceModeService.setFlagDirForTesting(directory.path);
    addTearDown(() {
      InstanceModeService.setFlagDirForTesting(null);
      directory.deleteSync(recursive: true);
    });
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_volume': 25.0},
    );
    final player = _GatedPlayer();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/audit/volume.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.volumes.last, 25.0);
    await tester.runAsync(services.settings.resetAll);
    await tester.pumpAndSettle();
    expect(player.volumes.last, 100.0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    services.settings.dispose();
  });
}
