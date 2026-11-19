import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/player_remote.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/windows_shell_service.dart';
import 'package:dacx/theme/window_visuals.dart';

import '../support/audit9_report.dart';
import '../support/method_channel_recorder.dart';
import '../support/player_screen_harness.dart';

typedef _Rig = ({
  HeadlessPlayerService player,
  SettingsService settings,
  PlayerRemote remote,
  StreamController<MediaSessionCommand> commands,
});

Future<_Rig> _pump(
  WidgetTester tester, {
  PlayableSource? source,
  List<PlayableSource>? playlist,
  PlayableSource? pending,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  final player = HeadlessPlayerService();
  final remote = PlayerRemote();
  final commands = StreamController<MediaSessionCommand>.broadcast();
  addTearDown(commands.close);
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        extensions: [
          WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
        ],
      ),
      home: PlayerScreen(
        settings: services.settings,
        debugLog: services.debugLog,
        updateService: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: source,
        initialPlaylistSources: playlist,
        initialPendingLoad: pending,
        playerRemote: remote,
        mediaSessionCommandsForTesting: commands,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _settle(tester);
  return (
    player: player,
    settings: services.settings,
    remote: remote,
    commands: commands,
  );
}

Future<void> _settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<Map<Object?, Object?>> _taskbarArgs() => [
  for (final call in PlayerScreenHarness.windowMethodsCalls)
    if (call.method == 'setTaskbarProgress')
      call.arguments as Map<Object?, Object?>,
];

void _expectTaskbar(
  void Function(List<Map<Object?, Object?>> calls) onWindows,
) {
  final calls = _taskbarArgs();
  if (!Platform.isWindows) {
    expect(calls, isEmpty);
    return;
  }
  onWindows(calls);
}

double _progress(Map<Object?, Object?> args) =>
    (args['progress'] as num).toDouble();

bool _isClear(Map<Object?, Object?> args) => _progress(args) < 0;

List<Map<Object?, Object?>> _mediaUpdates(MethodChannelRecorder recorder) => [
  for (final call in recorder.calls)
    if (call.method == 'update' && (call.arguments as Map).containsKey('title'))
      call.arguments as Map<Object?, Object?>,
];

final _clip = PlayableSource.file('/media/clip.mp4');
final _song = PlayableSource.file('/media/song.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'windows-shell',
    expectedIds: [
      for (var i = 1; i <= 7; i++) 'M46.$i',
      for (var i = 1; i <= 6; i++) 'M47.$i',
    ],
  );

  final mediaRecorder = MethodChannelRecorder('run.rosie.dacx/media_session');

  setUp(() {
    PlayerScreenHarness.installChannelMocks();
    mediaRecorder.install();
  });
  tearDown(() {
    mediaRecorder.uninstall();
    PlayerScreenHarness.uninstallChannelMocks();
  });
  tearDownAll(report.write);

  group('Finding 46: Windows taskbar progress on pause', () {
    test('M46.2 paused progress is sent as a map with paused true', () async {
      await WindowsShellService.setTaskbarProgress(0.5, paused: true);
      _expectTaskbar((calls) {
        expect(calls, hasLength(1));
        expect(_progress(calls.single), closeTo(0.5, 0.001));
        expect(calls.single['paused'], isTrue);
      });
      final bridge = File('windows/runner/window_bridge.cpp')
          .readAsStringSync();
      expect(bridge, contains('TBPF_PAUSED'));
      report.pass('M46.2');
    });

    test('M46.3 progress without paused is sent as not paused', () async {
      await WindowsShellService.setTaskbarProgress(0.5);
      _expectTaskbar((calls) {
        expect(calls, hasLength(1));
        expect(_progress(calls.single), closeTo(0.5, 0.001));
        expect(calls.single['paused'], isFalse);
      });
      report.pass('M46.3');
    });

    testWidgets(
      'M46.1 pausing with media loaded shows a paused bar at the position',
      (tester) async {
        final rig = await _pump(tester, source: _clip);
        rig.player.emitDuration(const Duration(seconds: 100));
        rig.player.emitPlaying(true);
        await _settle(tester);
        rig.player.emitPosition(const Duration(seconds: 40));
        await _settle(tester);
        rig.player.emitPlaying(false);
        await _settle(tester);
        _expectTaskbar((calls) {
          expect(calls, isNotEmpty);
          expect(calls.last['paused'], isTrue);
          expect(_isClear(calls.last), isFalse);
          expect(_progress(calls.last), closeTo(0.4, 0.001));
        });
        report.pass('M46.1');
      },
    );

    testWidgets('M46.4 stop, end of file and no media clear the bar', (
      tester,
    ) async {
      final stopped = await _pump(tester, source: _clip);
      stopped.player.emitDuration(const Duration(seconds: 100));
      stopped.player.emitPlaying(true);
      await _settle(tester);
      stopped.player.emitPosition(const Duration(seconds: 40));
      await _settle(tester);
      stopped.player.emitPlaying(false);
      await _settle(tester);
      stopped.commands.add(const MediaSessionCommand('stop', null));
      await _settle(tester, steps: 20);
      _expectTaskbar((calls) {
        expect(_isClear(calls.last), isTrue);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);

      PlayerScreenHarness.windowMethodsCalls.clear();
      final ended = await _pump(tester, source: _clip);
      ended.player.emitDuration(const Duration(seconds: 100));
      ended.player.emitPlaying(true);
      await _settle(tester);
      ended.player.emitPosition(const Duration(seconds: 100));
      await _settle(tester);
      ended.player.emitPlaying(false);
      ended.player.emitCompleted(true);
      await _settle(tester);
      _expectTaskbar((calls) {
        expect(_isClear(calls.last), isTrue);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);

      PlayerScreenHarness.windowMethodsCalls.clear();
      final reset = await _pump(tester, source: _clip);
      reset.player.emitDuration(const Duration(seconds: 100));
      reset.player.emitPlaying(true);
      await _settle(tester);
      reset.player.emitPosition(const Duration(seconds: 100));
      await _settle(tester);
      PlayerScreenHarness.windowMethodsCalls.clear();
      reset.player.emitCompleted(true);
      await _settle(tester);
      reset.player.emitPosition(Duration.zero);
      await _settle(tester);
      reset.player.emitPlaying(false);
      await _settle(tester);
      _expectTaskbar((calls) {
        expect(calls, isNotEmpty);
        expect(calls.where((args) => args['paused'] == true), isEmpty);
        expect(_isClear(calls.last), isTrue);
      });
      PlayerScreenHarness.windowMethodsCalls.clear();
      reset.player.emitPlaying(true);
      await _settle(tester);
      _expectTaskbar((calls) {
        expect(calls, isNotEmpty);
        expect(calls.last['paused'], isFalse);
        expect(_isClear(calls.last), isFalse);
        expect(_progress(calls.last), closeTo(0.0, 0.001));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);

      PlayerScreenHarness.windowMethodsCalls.clear();
      final empty = await _pump(tester);
      empty.player.emitDuration(const Duration(seconds: 100));
      empty.player.emitPlaying(false);
      await _settle(tester);
      _expectTaskbar((calls) {
        expect(calls, isNotEmpty);
        expect(_isClear(calls.last), isTrue);
      });
      report.pass('M46.4');
    });

    testWidgets('M46.5 resuming after pause shows normal progress', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      rig.player.emitDuration(const Duration(seconds: 100));
      rig.player.emitPlaying(true);
      await _settle(tester);
      rig.player.emitPosition(const Duration(seconds: 40));
      await _settle(tester);
      rig.player.emitPlaying(false);
      await _settle(tester);
      rig.player.emitPlaying(true);
      await _settle(tester);
      _expectTaskbar((calls) {
        expect(calls.last['paused'], isFalse);
        expect(_isClear(calls.last), isFalse);
        expect(_progress(calls.last), closeTo(0.4, 0.001));
      });
      report.pass('M46.5');
    });

    testWidgets(
      'M46.6 progress is clamped and unknown duration sends nothing',
      (tester) async {
        await WindowsShellService.setTaskbarProgress(1.7);
        await WindowsShellService.setTaskbarProgress(-0.5);
        await WindowsShellService.clearTaskbarProgress();
        _expectTaskbar((calls) {
          expect(calls, hasLength(3));
          expect(_progress(calls[0]), 1.0);
          expect(_progress(calls[1]), 0.0);
          expect(_isClear(calls[2]), isTrue);
        });
        PlayerScreenHarness.windowMethodsCalls.clear();

        final rig = await _pump(tester, source: _clip);
        rig.player.emitPlaying(true);
        await _settle(tester);
        rig.player.emitPosition(const Duration(seconds: 5));
        await _settle(tester);
        rig.player.emitPlaying(false);
        await _settle(tester);
        _expectTaskbar((calls) {
          expect(calls, isEmpty);
        });
        report.pass('M46.6');
      },
    );

    test('M46.7 the taskbar channel is only used on Windows', () async {
      await WindowsShellService.setTaskbarProgress(0.5, paused: true);
      await WindowsShellService.clearTaskbarProgress();
      if (Platform.isWindows) {
        final source = File('lib/services/windows_shell_service.dart')
            .readAsStringSync();
        final body = source.substring(
          source.indexOf('static Future<void> _invokeTaskbarProgress'),
        );
        expect(
          body.indexOf('if (!Platform.isWindows) return;'),
          lessThan(body.indexOf('invokeMethod')),
        );
      } else {
        expect(_taskbarArgs(), isEmpty);
      }
      report.pass('M46.7');
    });
  });

  group('Finding 47: Windows media type and unused rate field', () {
    testWidgets('M47.1 video metadata carries mediaType video', (tester) async {
      await _pump(tester, pending: _clip);
      if (!Platform.isWindows) {
        report.pass('M47.1');
        return;
      }
      final updates = _mediaUpdates(mediaRecorder);
      expect(updates, isNotEmpty);
      expect(updates.last['mediaType'], 'video');
      report.pass('M47.1');
    });

    testWidgets('M47.2 audio metadata carries mediaType music', (tester) async {
      await _pump(tester, pending: _song);
      if (!Platform.isWindows) {
        report.pass('M47.2');
        return;
      }
      final updates = _mediaUpdates(mediaRecorder);
      expect(updates, isNotEmpty);
      expect(updates.last['mediaType'], 'music');
      report.pass('M47.2');
    });

    test(
      'M47.3 position and playback updates never carry a media type',
      () async {
        if (!Platform.isWindows) {
          report.pass('M47.3');
          return;
        }
        final svc = MediaSessionService(
          debugLog: DebugLogService(isEnabled: () => true),
        );
        await svc.init(enabled: true);
        mediaRecorder.calls.clear();
        await svc.updateMetadata(title: 'Clip', isAudio: false);
        expect(_mediaUpdates(mediaRecorder).last['mediaType'], 'video');
        mediaRecorder.calls.clear();
        await svc.updatePosition(const Duration(seconds: 5), playing: true);
        await svc.updateLoop('loop');
        await svc.updateShuffle(true);
        await svc.updateVolume(0.5);
        await svc.updateRate(1.5);
        final updates = mediaRecorder.calls
            .where((c) => c.method == 'update')
            .map((c) => c.arguments as Map<Object?, Object?>)
            .toList();
        expect(updates, hasLength(5));
        for (final args in updates) {
          expect(args.containsKey('mediaType'), isFalse);
        }
        await svc.dispose();
        report.pass('M47.3');
      },
    );

    testWidgets('M47.4 switching from video to audio sends music', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip, playlist: [_clip, _song]);
      await rig.remote.next();
      await _settle(tester);
      if (!Platform.isWindows) {
        report.pass('M47.4');
        return;
      }
      final updates = _mediaUpdates(mediaRecorder);
      expect(updates, isNotEmpty);
      expect(updates.last['mediaType'], 'music');
      report.pass('M47.4');
    });

    test('M47.5 last_rate_ is gone from the native media session', () {
      for (final path in [
        'windows/runner/media_session.cpp',
        'windows/runner/media_session.h',
      ]) {
        expect(File(path).readAsStringSync(), isNot(contains('last_rate_')));
      }
      report.pass('M47.5');
    });

    test('M47.6 the native update handler reads mediaType and sets video', () {
      final source = File('windows/runner/media_session.cpp')
          .readAsStringSync();
      expect(source, contains('"mediaType"'));
      expect(source, contains('MediaPlaybackType::Video'));
      expect(source, contains('MediaPlaybackType::Music'));
      report.pass('M47.6');
    });
  });
}
