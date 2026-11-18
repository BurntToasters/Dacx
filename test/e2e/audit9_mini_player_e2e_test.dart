import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/player_window_controller.dart';
import 'package:dacx/screens/player/widgets/media_surface.dart';
import 'package:dacx/screens/player/widgets/player_bottom_dock.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/compact_exit_button.dart';
import 'package:dacx/widgets/custom_title_bar.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _opacityKey = Key('mini-player-overlay-opacity');
const _ignoreKey = Key('mini-player-overlay-ignore');
const _titleKey = Key('mini-player-title');
const _artistKey = Key('mini-player-artist');
const _prevKey = Key('mini-player-prev');
const _playPauseKey = Key('mini-player-play-pause');
const _nextKey = Key('mini-player-next');
const _seekKey = Key('mini-player-seek');
const _audioIconKey = Key('mini-player-audio-icon');
const _audioArtKey = Key('mini-player-audio-art');
const _surfaceCenter = Offset(800, 500);
const _normalMinimum = Size(480, 320);
const _miniMinimum = Size(240, 135);

class _Player extends HeadlessPlayerService {
  final Map<String, Map<String, String>> tags = {};
  final List<Duration> seeks = [];

  @override
  Future<String?> getProperty(String name) async {
    const prefix = 'metadata/by-key/';
    if (!name.startsWith(prefix)) return super.getProperty(name);
    final path = await super.getProperty('path');
    return tags[path]?[name.substring(prefix.length)];
  }

  @override
  Future<void> seek(Duration position) {
    seeks.add(position);
    return super.seek(position);
  }
}

class _WindowMock {
  Size size = const Size(1200, 800);
  Offset position = const Offset(40, 60);
  bool fullscreen = false;
  bool Function(MethodCall call)? fail;
  final List<MethodCall> calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PlayerScreenHarness.windowManagerChannel,
          handle,
        );
  }

  List<MethodCall> of(String method) => [
    for (final call in calls)
      if (call.method == method) call,
  ];

  List<double> get aspects => [
    for (final call in of('setAspectRatio'))
      ((call.arguments as Map)['aspectRatio'] as num).toDouble(),
  ];

  List<Size> get minimums => [
    for (final call in of('setMinimumSize'))
      Size(
        ((call.arguments as Map)['width'] as num).toDouble(),
        ((call.arguments as Map)['height'] as num).toDouble(),
      ),
  ];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final failing = fail;
    if (failing != null && failing(call)) {
      throw PlatformException(code: 'window_call_failed');
    }
    switch (call.method) {
      case 'isMaximized':
      case 'isMinimized':
        return false;
      case 'isFullScreen':
        return fullscreen;
      case 'setFullScreen':
        final args = call.arguments;
        fullscreen = args is bool
            ? args
            : (args as Map<Object?, Object?>)['isFullScreen'] as bool? ?? false;
        return null;
      case 'getBounds':
        return {
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        };
      case 'setBounds':
        final args = call.arguments as Map<Object?, Object?>;
        final width = args['width'];
        final height = args['height'];
        if (width is num && height is num) {
          size = Size(width.toDouble(), height.toDouble());
        }
        final x = args['x'];
        final y = args['y'];
        if (x is num && y is num) {
          position = Offset(x.toDouble(), y.toDouble());
        }
        return null;
      case 'getTitleBarHeight':
        return 0;
      default:
        return null;
    }
  }
}

typedef _Rig = ({_WindowMock win, _Player player, SettingsService settings});

Future<_Rig> _pump(
  WidgetTester tester, {
  PlayableSource? source,
  List<PlayableSource>? playlist,
  PlayableSource? pending,
  LoopMode? loop,
  _Player? player,
  _WindowMock? win,
  ValueChanged<bool>? onCompact,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  if (loop != null) services.settings.loopMode = loop;
  final window = win ?? _WindowMock();
  window.install();
  final service = player ?? _Player();
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
        playerService: service,
        headlessMediaSurface: true,
        initialLoadedSource: source,
        initialPlaylistSources: playlist,
        initialPendingLoad: pending,
        onCompactModeChanged: onCompact,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (win: window, player: service, settings: services.settings);
}

Future<void> _settle(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _toggleMini(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await _settle(tester);
}

Future<void> _elapse(WidgetTester tester, int milliseconds) =>
    tester.pump(Duration(milliseconds: milliseconds));

bool _shown(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_opacityKey)).opacity > 0.5;

bool _ignoring(WidgetTester tester) =>
    tester.widget<IgnorePointer>(find.byKey(_ignoreKey)).ignoring;

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key)).onPressed != null;

String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

Rect _scaffoldRect(WidgetTester tester) =>
    tester.getRect(find.byType(Scaffold).first);

Future<TestGesture> _mouseAt(WidgetTester tester, Offset position) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: position);
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

Future<void> _setVideoSize(_Player player, int width, int height) async {
  await player.setProperty('dwidth', '$width');
  await player.setProperty('dheight', '$height');
  player.emitVideoWidth(width);
}

Tracks _artTracks() => const Tracks(
  audio: [AudioTrack('a1', 'eng', null)],
  video: [VideoTrack('art', 'Album art', null, albumart: true)],
  subtitle: [],
);

final _a = PlayableSource.file('/media/a.mp3');
final _b = PlayableSource.file('/media/b.mp3');
final _c = PlayableSource.file('/media/c.mp3');
final _clip = PlayableSource.file('/media/clip.mp4');
final _song = PlayableSource.file('/media/song.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'mini-player',
    expectedIds: [for (var i = 1; i <= 22; i++) 'M19.$i'],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 19: mini-player layout', () {
    testWidgets('M19.1 no title bar and no dock in the mini-player', (
      tester,
    ) async {
      await _pump(tester, source: _clip);
      await tester.pumpAndSettle();
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(find.byType(PlayerBottomDock), findsOneWidget);

      await _toggleMini(tester);
      expect(find.byType(CustomTitleBar), findsNothing);
      expect(find.byType(PlayerBottomDock), findsNothing);
      expect(find.byKey(const Key('mini-player-layout')), findsOneWidget);
      report.pass('M19.1');
    });

    testWidgets('M19.2 the media surface fills the window', (tester) async {
      await _pump(tester, source: _clip);
      await _toggleMini(tester);

      expect(tester.getRect(find.byType(MediaSurface)), _scaffoldRect(tester));
      await _elapse(tester, 4000);
      expect(_shown(tester), isFalse);
      expect(tester.getRect(find.byType(MediaSurface)), _scaffoldRect(tester));
      report.pass('M19.2');
    });

    testWidgets('M19.3 overlay shows on hover and hides after idle', (
      tester,
    ) async {
      await _pump(tester, source: _clip);
      await _toggleMini(tester);
      expect(_shown(tester), isTrue);

      final mouse = await _mouseAt(tester, _surfaceCenter);
      await mouse.moveTo(_surfaceCenter + const Offset(10, 0));
      await tester.pump();
      await _elapse(tester, 1800);
      expect(_shown(tester), isTrue);
      await _elapse(tester, 400);
      expect(_shown(tester), isFalse);

      await mouse.moveTo(_surfaceCenter + const Offset(30, 10));
      await tester.pump();
      expect(_shown(tester), isTrue);

      await _elapse(tester, 1500);
      await mouse.moveTo(_surfaceCenter + const Offset(60, 20));
      await tester.pump();
      await _elapse(tester, 1500);
      expect(_shown(tester), isTrue);
      await _elapse(tester, 700);
      expect(_shown(tester), isFalse);

      await mouse.moveTo(_surfaceCenter + const Offset(90, 30));
      await tester.pump();
      await _elapse(tester, 1000);
      await mouse.moveTo(const Offset(-200, -200));
      await tester.pump();
      await _elapse(tester, 1500);
      expect(_shown(tester), isTrue);
      await _elapse(tester, 700);
      expect(_shown(tester), isFalse);
      report.pass('M19.3');
    });

    testWidgets('M19.4 a pointer down on a control keeps the overlay', (
      tester,
    ) async {
      await _pump(tester, source: _clip);
      await _toggleMini(tester);
      final target = tester.getCenter(find.byKey(_playPauseKey));

      final touch = await tester.startGesture(
        target,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await _elapse(tester, 10000);
      expect(_shown(tester), isTrue);
      await touch.up();
      await tester.pump();
      await _elapse(tester, 1800);
      expect(_shown(tester), isTrue);
      await _elapse(tester, 400);
      expect(_shown(tester), isFalse);

      await tester.tapAt(_surfaceCenter + const Offset(5, 5));
      await _elapse(tester, 400);
      expect(_shown(tester), isTrue);
      final held = await tester.startGesture(
        tester.getCenter(find.byKey(_playPauseKey)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await _elapse(tester, 10000);
      expect(_shown(tester), isTrue);
      await held.cancel();
      await tester.pump();
      await _elapse(tester, 1800);
      expect(_shown(tester), isTrue);
      await _elapse(tester, 400);
      expect(_shown(tester), isFalse);
      report.pass('M19.4');
    });

    testWidgets('M19.5 a hidden overlay ignores pointer input', (tester) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b]);
      await _toggleMini(tester);
      expect(_ignoring(tester), isFalse);
      final nextCenter = tester.getCenter(find.byKey(_nextKey));

      await _elapse(tester, 4000);
      expect(_shown(tester), isFalse);
      expect(_ignoring(tester), isTrue);

      await tester.tapAt(nextCenter);
      await _elapse(tester, 400);
      expect(rig.player.playPauseInvocations, 1);
      expect(rig.player.openCalls, isEmpty);
      report.pass('M19.5');
    });

    testWidgets('M19.6 previous and next follow the queue policy', (
      tester,
    ) async {
      final empty = await _pump(tester);
      await _toggleMini(tester);
      expect(_enabled(tester, _prevKey), isFalse);
      expect(_enabled(tester, _playPauseKey), isFalse);
      expect(_enabled(tester, _nextKey), isFalse);
      expect(empty.player.openCalls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());

      await _pump(tester, source: _clip);
      await _toggleMini(tester);
      expect(_enabled(tester, _playPauseKey), isTrue);
      expect(_enabled(tester, _prevKey), isFalse);
      expect(_enabled(tester, _nextKey), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());

      await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      await _toggleMini(tester);
      expect(_enabled(tester, _prevKey), isFalse);
      expect(_enabled(tester, _nextKey), isTrue);

      await tester.tap(find.byKey(_nextKey));
      await _settle(tester);
      expect(_enabled(tester, _prevKey), isTrue);
      expect(_enabled(tester, _nextKey), isTrue);

      await tester.tap(find.byKey(_nextKey));
      await _settle(tester);
      expect(_enabled(tester, _prevKey), isTrue);
      expect(_enabled(tester, _nextKey), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());

      await _pump(
        tester,
        source: _a,
        playlist: [_a, _b, _c],
        loop: LoopMode.loop,
      );
      await _toggleMini(tester);
      expect(_enabled(tester, _prevKey), isTrue);
      expect(_enabled(tester, _nextKey), isTrue);
      report.pass('M19.6');
    });

    testWidgets('M19.7 transport buttons drive playback', (tester) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      await _toggleMini(tester);

      await tester.tap(find.byKey(_playPauseKey));
      await _settle(tester);
      expect(rig.player.playPauseInvocations, 1);

      await tester.tap(find.byKey(_nextKey));
      await _settle(tester);
      expect(rig.player.openCalls.last.path, _b.value);

      await tester.tap(find.byKey(_prevKey));
      await _settle(tester);
      expect(rig.player.openCalls.last.path, _a.value);
      expect(rig.player.openCalls.length, 2);
      report.pass('M19.7');
    });

    testWidgets('M19.8 audio shows icon, title and artist; video no artist', (
      tester,
    ) async {
      final tagged = _Player()
        ..tags[_song.value] = {'title': 'Song Title', 'artist': 'The Artist'};
      await _pump(tester, pending: _song, player: tagged);
      await _settle(tester);
      await _toggleMini(tester);
      expect(find.byKey(_audioIconKey), findsOneWidget);
      expect(find.byKey(_audioArtKey), findsNothing);
      expect(_textOf(tester, _titleKey), 'Song Title');
      expect(_textOf(tester, _artistKey), 'The Artist');
      await tester.pumpWidget(const SizedBox.shrink());

      await _pump(tester, pending: PlayableSource.file('/media/plain.flac'));
      await _settle(tester);
      await _toggleMini(tester);
      expect(find.byKey(_audioIconKey), findsOneWidget);
      expect(_textOf(tester, _titleKey), 'plain.flac');
      expect(find.byKey(_artistKey), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());

      final video = _Player()
        ..tags[_clip.value] = {'title': 'Clip Title', 'artist': 'Someone'};
      await _pump(tester, pending: _clip, player: video);
      await _settle(tester);
      await _toggleMini(tester);
      expect(_textOf(tester, _titleKey), 'Clip Title');
      expect(find.byKey(_artistKey), findsNothing);
      expect(find.text('Someone'), findsNothing);
      expect(find.byKey(_audioIconKey), findsNothing);
      report.pass('M19.8');
    });

    testWidgets('M19.9 cover art fills the window behind the overlay', (
      tester,
    ) async {
      final tagged = _Player()
        ..tags[_song.value] = {'title': 'Song Title', 'artist': 'The Artist'};
      await _pump(tester, pending: _song, player: tagged);
      await _settle(tester);
      tagged.emitTracks(_artTracks());
      await _settle(tester);
      await _toggleMini(tester);

      expect(find.byKey(_audioArtKey), findsOneWidget);
      expect(find.byKey(_audioIconKey), findsNothing);
      expect(tester.getRect(find.byKey(_audioArtKey)), _scaffoldRect(tester));
      expect(_textOf(tester, _titleKey), 'Song Title');
      expect(_textOf(tester, _artistKey), 'The Artist');
      expect(_shown(tester), isTrue);
      report.pass('M19.9');
    });

    testWidgets('M19.10 entering with a known video sets the aspect ratio', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);
      expect(rig.win.aspects, isEmpty);

      await _toggleMini(tester);
      expect(rig.win.aspects, hasLength(1));
      expect(rig.win.aspects.single, closeTo(1920 / 1080, 0.001));
      expect(rig.win.size.width, closeTo(480, 0.5));
      expect(rig.win.size.height, closeTo(270, 1));
      report.pass('M19.10');
    });

    testWidgets('M19.11 later or changed video sizes update the aspect', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _toggleMini(tester);
      expect(rig.win.aspects, isEmpty);

      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);
      expect(rig.win.aspects, hasLength(1));
      expect(rig.win.aspects.last, closeTo(16 / 9, 0.001));

      await _setVideoSize(rig.player, 1280, 1024);
      await _settle(tester);
      expect(rig.win.aspects.last, closeTo(1.25, 0.001));
      expect(rig.win.size.width, closeTo(480, 0.5));
      expect(rig.win.size.height, closeTo(384, 1));
      report.pass('M19.11');
    });

    testWidgets('M19.12 minimum size is lowered then restored in order', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);

      await _toggleMini(tester);
      expect(rig.win.minimums.last, _miniMinimum);
      expect(rig.win.aspects.last, closeTo(16 / 9, 0.001));

      final mark = rig.win.calls.length;
      await _toggleMini(tester);
      final after = rig.win.calls.sublist(mark);
      final aspectAt = after.indexWhere((c) => c.method == 'setAspectRatio');
      final minimumAt = after.indexWhere((c) => c.method == 'setMinimumSize');
      final boundsAt = after.lastIndexWhere((c) => c.method == 'setBounds');
      expect(aspectAt, greaterThanOrEqualTo(0));
      expect(
        ((after[aspectAt].arguments as Map)['aspectRatio'] as num).toDouble(),
        0,
      );
      expect(minimumAt, greaterThan(aspectAt));
      expect(rig.win.minimums.last, _normalMinimum);
      expect(boundsAt, greaterThan(minimumAt));
      expect(rig.win.size, const Size(1200, 800));
      report.pass('M19.12');
    });

    testWidgets('M19.13 audio never locks the aspect ratio', (tester) async {
      final audio = await _pump(tester, source: _song);
      await _toggleMini(tester);
      expect(audio.win.aspects, isEmpty);
      expect(audio.win.minimums.last, _miniMinimum);
      await tester.pumpWidget(const SizedBox.shrink());

      final rig = await _pump(tester, source: _clip, playlist: [_clip, _song]);
      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);
      await _toggleMini(tester);
      expect(rig.win.aspects.last, closeTo(16 / 9, 0.001));

      await tester.tap(find.byKey(_nextKey));
      await _settle(tester);
      rig.player.emitTracks(
        const Tracks(audio: [AudioTrack('a1', 'eng', null)], video: []),
      );
      await _settle(tester);
      expect(rig.win.aspects.last, 0);
      report.pass('M19.13');
    });

    testWidgets('M19.14 double-click leaves the mini-player', (tester) async {
      final reported = <bool>[];
      final rig = await _pump(tester, source: _clip, onCompact: reported.add);
      await _toggleMini(tester);
      expect(reported, [true]);

      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(_surfaceCenter);
      await _settle(tester);
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(find.byType(PlayerBottomDock), findsOneWidget);
      expect(reported, [true, false]);
      expect(rig.win.of('setFullScreen'), isEmpty);
      expect(rig.player.playPauseInvocations, 0);

      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(_surfaceCenter);
      await _settle(tester);
      expect(rig.win.of('setFullScreen'), hasLength(1));
      report.pass('M19.14');
    });

    testWidgets('M19.15 dragging the surface starts a window drag', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _toggleMini(tester);

      await tester.tapAt(_surfaceCenter);
      await _elapse(tester, 400);
      expect(rig.win.of('startDragging'), isEmpty);

      await tester.dragFrom(_surfaceCenter, const Offset(120, 40));
      await _settle(tester);
      expect(rig.win.of('startDragging'), hasLength(1));

      await tester.dragFrom(_surfaceCenter, const Offset(-90, 30));
      await _settle(tester);
      expect(rig.win.of('startDragging'), hasLength(2));

      rig.player.emitDuration(const Duration(seconds: 100));
      await _settle(tester);
      await tester.drag(find.byKey(_seekKey), const Offset(60, 0));
      await _settle(tester);
      expect(rig.win.of('startDragging'), hasLength(2));

      PlayerWindowController.debugLinuxOverride = true;
      addTearDown(() => PlayerWindowController.debugLinuxOverride = null);
      await tester.dragFrom(_surfaceCenter, const Offset(100, 20));
      await _settle(tester);
      expect(rig.win.of('startDragging'), hasLength(2));
      report.pass('M19.15');
    });

    testWidgets('M19.16 leaving restores the normal window and layout', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await tester.pumpAndSettle();
      final normalSurface = tester.getRect(find.byType(MediaSurface));

      await _toggleMini(tester);
      expect(rig.win.of('setAlwaysOnTop').last.arguments, {
        'isAlwaysOnTop': true,
      });
      expect(rig.win.size.width, closeTo(480, 0.5));

      await _toggleMini(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(find.byType(PlayerBottomDock), findsOneWidget);
      expect(find.byKey(const Key('mini-player-layout')), findsNothing);
      expect(tester.getRect(find.byType(MediaSurface)), normalSurface);
      expect(
        tester.getRect(find.byType(MediaSurface)).height,
        lessThan(_scaffoldRect(tester).height),
      );
      expect(rig.win.size, const Size(1200, 800));
      expect(rig.win.position, const Offset(40, 60));
      expect(rig.win.of('setAlwaysOnTop').last.arguments, {
        'isAlwaysOnTop': false,
      });
      expect(rig.win.minimums.last, _normalMinimum);
      report.pass('M19.16');
    });

    testWidgets('M19.17 the exit button leaves the mini-player', (
      tester,
    ) async {
      final reported = <bool>[];
      await _pump(tester, source: _clip, onCompact: reported.add);
      await _toggleMini(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);

      await tester.tap(find.byType(CompactExitButton));
      await _settle(tester);
      expect(reported, [true, false]);
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(find.byType(CompactExitButton), findsNothing);
      report.pass('M19.17');
    });

    testWidgets('M19.18 a failed enter leaves no constraints behind', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);

      rig.win.fail = (call) =>
          call.method == 'setBounds' && (call.arguments as Map)['width'] == 480;
      await _toggleMini(tester);
      expect(find.byType(CustomTitleBar), findsOneWidget);
      expect(find.byType(PlayerBottomDock), findsOneWidget);
      expect(find.byKey(const Key('mini-player-layout')), findsNothing);
      expect(rig.win.minimums.last, _normalMinimum);
      expect(
        rig.win.aspects.isEmpty || rig.win.aspects.last == 0,
        isTrue,
        reason: 'no aspect lock may survive a failed enter',
      );
      report.pass('M19.18');
    });

    testWidgets('M19.19 a failed leave keeps the mini constraints', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      await _setVideoSize(rig.player, 1920, 1080);
      await _settle(tester);
      await _toggleMini(tester);
      expect(find.byKey(const Key('mini-player-layout')), findsOneWidget);

      rig.win.fail = (call) =>
          call.method == 'setBounds' &&
          (call.arguments as Map)['width'] == 1200;
      await _toggleMini(tester);
      expect(find.byKey(const Key('mini-player-layout')), findsOneWidget);
      expect(find.byType(CustomTitleBar), findsNothing);
      expect(rig.win.minimums.last, _miniMinimum);
      expect(rig.win.aspects.last, closeTo(16 / 9, 0.001));
      report.pass('M19.19');
    });

    testWidgets('M19.20 the seek bar shows position and seeks on release', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      rig.player.emitDuration(const Duration(seconds: 100));
      await _toggleMini(tester);
      rig.player.emitPosition(const Duration(seconds: 25));
      await _settle(tester);

      final slider = tester.widget<Slider>(find.byKey(_seekKey));
      expect(slider.value, closeTo(25000, 1));
      expect(slider.max, closeTo(100000, 1));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_seekKey)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(rig.player.seeks, isEmpty);
      await gesture.up();
      await _settle(tester);
      expect(rig.player.seeks, hasLength(1));
      expect(rig.player.seeks.single, greaterThan(const Duration(seconds: 50)));
      report.pass('M19.20');
    });

    testWidgets('M19.21 the mini layout fits the 240x135 minimum', (
      tester,
    ) async {
      Future<void> check(Future<_Rig> Function() build) async {
        final rig = await build();
        await _toggleMini(tester);
        tester.view.physicalSize = _miniMinimum;
        await tester.pump();
        await _elapse(tester, 400);
        expect(tester.takeException(), isNull);
        expect(rig.win.calls, isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }

      const longTitle =
          'An extremely long track title that keeps going and going well '
          'past any reasonable width';
      await check(() async {
        final player = _Player()
          ..tags[_song.value] = {'title': longTitle, 'artist': longTitle};
        final rig = await _pump(tester, pending: _song, player: player);
        await _settle(tester);
        return rig;
      });
      await check(() async {
        final player = _Player()
          ..tags[_song.value] = {'title': longTitle, 'artist': longTitle};
        final rig = await _pump(tester, pending: _song, player: player);
        await _settle(tester);
        player.emitTracks(_artTracks());
        await _settle(tester);
        return rig;
      });
      await check(() async {
        final rig = await _pump(tester, source: _clip);
        rig.player.emitDuration(const Duration(minutes: 90));
        await _setVideoSize(rig.player, 1920, 1080);
        await _settle(tester);
        return rig;
      });
      await check(() => _pump(tester));
      report.pass('M19.21');
    });

    test('M19.22 lib/widgets never imports lib/screens', () {
      final offenders = <String>[];
      for (final entity in Directory('lib/widgets').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        final imports = RegExp(
          r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
          multiLine: true,
        ).allMatches(source);
        for (final match in imports) {
          final target = match.group(1)!;
          if (target.contains('screens/')) offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);

      final geometry = File('lib/widgets/widget_geometry.dart');
      expect(geometry.existsSync(), isTrue);
      expect(
        geometry.readAsStringSync(),
        contains('Rect? globalRectOfContext(BuildContext context)'),
      );
      var definitions = 0;
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains(
          'Rect? globalRectOfContext(BuildContext context)',
        )) {
          definitions++;
        }
      }
      expect(definitions, 1);
      report.pass('M19.22');
    });
  });
}
