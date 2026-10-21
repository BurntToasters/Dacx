// E2E acceptance coverage is intentionally written before the feature code.
// See ADVANCED_PLAYBACK_FAILURE_MODES.md for the complete failure inventory.
// This uses the existing desktop PlayerScreen harness so it can run in CI
// without requiring a bundled libmpv on the test host.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/widgets/seek_slider.dart';

import '../support/player_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  testWidgets('advanced playback stays hidden until opt-in', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/e2e/advanced.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    player.emitDuration(const Duration(minutes: 2));
    await tester.pump();

    expect(services.settings.advancedPlaybackToolsEnabled, isFalse);
    expect(find.byKey(const ValueKey('advanced-playback-entry')), findsNothing);
    expect(
      find.byKey(const ValueKey('advanced-playback-dialog')),
      findsNothing,
    );
    const advancedProperties = {
      'audio-delay',
      'sub-delay',
      'ab-loop-a',
      'ab-loop-b',
      'sub-font-size',
      'sub-pos',
      'sub-outline-size',
      'sub-color',
      'sub-border-color',
      'sub-ass-override',
    };
    expect(
      player.propertyCalls
          .map((call) => call.name)
          .toSet()
          .intersection(advancedProperties),
      isEmpty,
    );
  });

  testWidgets('opt-in dialog controls apply and persist playback state', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/e2e/advanced.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    player.emitDuration(const Duration(minutes: 2));
    player.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    services.settings.advancedPlaybackToolsEnabled = true;
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('advanced-playback-entry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('advanced-playback-dialog')),
      findsOneWidget,
    );
    expect(find.text('A-B repeat'), findsOneWidget);
    expect(find.text('Playback markers'), findsOneWidget);
    expect(find.text('Subtitle appearance'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('advanced-set-a')));
    await tester.pump();
    player.emitPosition(const Duration(seconds: 45));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('advanced-set-b')));
    await tester.pump();
    await tester.pump();
    expect(player.properties['ab-loop-a'], '30.000');
    expect(player.properties['ab-loop-b'], '45.000');

    await tester.tap(find.byKey(const ValueKey('advanced-add-marker')));
    await tester.pump();
    expect(
      services.settings.playbackMarkersFor('/e2e/advanced.mp3'),
      hasLength(1),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('advanced-disable')));
    await tester.tap(find.byKey(const ValueKey('advanced-disable')));
    await tester.pump();
    expect(services.settings.advancedPlaybackToolsEnabled, isFalse);
    expect(player.properties['audio-delay'], '0');
    expect(player.properties['sub-delay'], '0');
    expect(player.properties['ab-loop-a'], 'no');
    expect(player.properties['ab-loop-b'], 'no');
    expect(
      services.settings.playbackMarkersFor('/e2e/advanced.mp3'),
      hasLength(1),
    );
  });

  testWidgets('delay resets are independent and failed writes are visible', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/e2e/advanced.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    player.emitDuration(const Duration(minutes: 2));
    player.emitPosition(const Duration(seconds: 30));
    services.settings.advancedPlaybackToolsEnabled = true;
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('advanced-playback-entry')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('advanced-audio-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('advanced-subtitle-plus')));
    await tester.pump();
    expect(
      services.settings.playbackAdjustmentFor('/e2e/advanced.mp3').audioMs,
      100,
    );
    expect(
      services.settings.playbackAdjustmentFor('/e2e/advanced.mp3').subtitleMs,
      100,
    );

    await tester.tap(find.byKey(const ValueKey('advanced-audio-reset')));
    await tester.pump();
    var adjustment = services.settings.playbackAdjustmentFor(
      '/e2e/advanced.mp3',
    );
    expect(adjustment.audioMs, 0);
    expect(adjustment.subtitleMs, 100);
    await tester.tap(find.byKey(const ValueKey('advanced-subtitle-reset')));
    await tester.pump();
    adjustment = services.settings.playbackAdjustmentFor('/e2e/advanced.mp3');
    expect(adjustment.audioMs, 0);
    expect(adjustment.subtitleMs, 0);

    player.failProperties(['audio-delay']);
    await tester.tap(find.byKey(const ValueKey('advanced-audio-plus')));
    await tester.pump();
    expect(
      services.settings.playbackAdjustmentFor('/e2e/advanced.mp3').audioMs,
      0,
    );
    expect(find.text('Could not apply audio delay.'), findsOneWidget);
  });

  testWidgets('advanced shortcut rows follow the opt-in gate', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final off = await PlayerScreenHarness.createServices();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: off.settings,
        debugLog: off.debugLog,
        updates: off.updates,
        playerService: HeadlessPlayerService(),
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyboard shortcuts'));
    await tester.pumpAndSettle();
    final offShortcutList = find.byType(ListView).last;
    for (var i = 0; i < 5; i += 1) {
      await tester.drag(offShortcutList, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.text('A-B repeat'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    off.settings.advancedPlaybackToolsEnabled = true;
    await tester.pumpAndSettle();
    expect(off.settings.advancedPlaybackToolsEnabled, isTrue);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyboard shortcuts'));
    await tester.pumpAndSettle();
    final onShortcutList = find.byType(ListView).last;
    for (var i = 0; i < 5; i += 1) {
      await tester.drag(onShortcutList, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.text('A-B repeat'), findsOneWidget);
  });

  testWidgets('advanced data rejects malformed values and reset clears it', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {
        'advanced_playback_tools_enabled': true,
        'playback_adjustments_v1':
            '{"/e2e/advanced.mp3":{"a":999999,"s":"bad"}}',
        'playback_markers_v1':
            '{"/e2e/advanced.mp3":[{"p":-1,"label":"\u0000bad"}]}',
      },
    );
    expect(
      services.settings.playbackAdjustmentFor('/e2e/advanced.mp3').audioMs,
      0,
    );
    expect(services.settings.playbackMarkersFor('/e2e/advanced.mp3'), isEmpty);

    final oversizedAdjustments = <String, Object?>{};
    final oversizedMarkers = <String, Object?>{};
    for (var i = 0; i < 101; i += 1) {
      final path = '/e2e/source-$i.mp3';
      oversizedAdjustments[path] = {'a': 100, 's': 0, 't': i + 1};
      oversizedMarkers[path] = {
        't': i + 1,
        'markers': [
          {'id': 'm$i', 'p': 1000, 'label': 'Marker'},
        ],
      };
    }
    final bounded = await PlayerScreenHarness.createServices(
      prefs: {
        'playback_adjustments_v1': jsonEncode(oversizedAdjustments),
        'playback_markers_v1': jsonEncode(oversizedMarkers),
      },
    );
    expect(
      bounded.settings.playbackAdjustmentFor('/e2e/source-100.mp3').audioMs,
      0,
    );
    expect(bounded.settings.playbackMarkersFor('/e2e/source-100.mp3'), isEmpty);

    final malformed = await PlayerScreenHarness.createServices(
      prefs: {
        'playback_markers_v1': jsonEncode({
          '/e2e/corrupt.mp3': {
            't': 1,
            'markers': List.generate(
              51,
              (i) => {'id': 'm$i', 'p': 1, 'label': 'Marker'},
            ),
          },
        }),
      },
    );
    expect(malformed.settings.playbackMarkersFor('/e2e/corrupt.mp3'), isEmpty);

    await services.settings.resetAll();
    expect(services.settings.advancedPlaybackToolsEnabled, isFalse);
    expect(services.settings.playbackMarkersFor('/e2e/advanced.mp3'), isEmpty);
  });

  test('E2E acceptance artifact is repeatable JSON', () {
    final fixturePath = Platform.environment['DACX_E2E_FIXTURE'];
    final fixture = fixturePath == null ? null : File(fixturePath);
    final outputPath =
        Platform.environment['DACX_E2E_REPORT'] ??
        'test-results/e2e/${Platform.operatingSystem}/advanced-playback-report.json';
    final root = File(outputPath).parent;
    root.createSync(recursive: true);
    final runnerStatus = Platform.environment['DACX_E2E_STATUS'];
    final rawLogPath = Platform.environment['DACX_E2E_LOG'];
    final report = <String, Object?>{
      'schema': 'dacx.e2e.advanced-playback.v1',
      'status': runnerStatus ?? 'pending',
      'statusSource': runnerStatus == null ? 'runner-required' : 'runner',
      'suite': 'advanced-playback',
      'platform': Platform.operatingSystem,
      'fixtureHashes': fixture != null && fixture.existsSync()
          ? <String, String>{
              fixture.absolute.path: sha256
                  .convert(fixture.readAsBytesSync())
                  .toString(),
            }
          : <String, String>{},
      'rawLogHashes': rawLogPath != null && File(rawLogPath).existsSync()
          ? <String, String>{
              File(rawLogPath).absolute.path: sha256
                  .convert(File(rawLogPath).readAsBytesSync())
                  .toString(),
            }
          : <String, String>{},
      'checks': <String>[
        'opt-in-default',
        'off-startup-no-advanced-mpv-writes',
        'dialog-application',
        'independent-delay-resets',
        'gated-advanced-shortcuts',
        'malformed-data-fail-closed',
        'seek-marker-range-semantics',
        'reset-clears-stores',
      ],
    };
    File(outputPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    expect(report['status'], runnerStatus ?? 'pending');
  });

  testWidgets('seek markers and A-B ranges expose semantics', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SeekSliderWithHover(
            position: const Duration(seconds: 15),
            duration: const Duration(minutes: 1),
            markerPositions: const [
              SeekMarker(position: Duration(seconds: 15), label: 'Chapter one'),
            ],
            rangeStart: const Duration(seconds: 10),
            rangeEnd: const Duration(seconds: 20),
            onSeekStart: () {},
            onSeekChange: (_) {},
            onSeekEnd: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Playback marker: Chapter one'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('A-B repeat range: 00:10 to 00:20'),
      findsOneWidget,
    );
  });
}
