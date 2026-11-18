import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/widgets/media_surface.dart';
import 'package:dacx/screens/player/widgets/player_bottom_dock.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/headless_player_service.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _titleOverlay = ValueKey('fullscreen-title-overlay');
const _dockOverlay = ValueKey('fullscreen-dock-overlay');
const _overlayOpacity = ValueKey('chrome-overlay-opacity');
const _overlayIgnore = ValueKey('chrome-overlay-ignore');
const _surfaceCenter = Offset(800, 400);

Future<HeadlessPlayerService> _pumpPlayer(
  WidgetTester tester, {
  PlayableSource? source,
  List<PlayableSource>? playlist,
}) async {
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
      initialLoadedSource: source,
      initialPlaylistSources: playlist,
    ),
  );
  await tester.pump();
  await tester.pump();
  return player;
}

Future<void> _enterFullscreen(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(PlayerScreenHarness.fullscreenCalls.last, isTrue);
}

Future<void> _elapse(WidgetTester tester, Duration duration) =>
    tester.pump(duration);

bool _shown(WidgetTester tester, ValueKey<String> overlay) {
  final opacity = find.descendant(
    of: find.byKey(overlay),
    matching: find.byKey(_overlayOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity).opacity > 0.5;
}

bool _ignoring(WidgetTester tester, ValueKey<String> overlay) {
  final ignore = find.descendant(
    of: find.byKey(overlay),
    matching: find.byKey(_overlayIgnore),
  );
  return tester.widget<IgnorePointer>(ignore).ignoring;
}

Offset _dockCorner(WidgetTester tester) =>
    tester.getTopLeft(find.byType(PlayerBottomDock)) + const Offset(4, 4);

Future<TestGesture> _mouseAt(WidgetTester tester, Offset position) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: position);
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

Key? _switcherChildKey(WidgetTester tester) {
  final switcher = find
      .descendant(
        of: find.byType(MediaSurface),
        matching: find.byType(AnimatedSwitcher),
      )
      .first;
  return tester.widget<AnimatedSwitcher>(switcher).child?.key;
}

Tracks _artTracks() => const Tracks(
  audio: [AudioTrack('a1', 'eng', null)],
  video: [VideoTrack('art', 'Album art', null, albumart: true)],
  subtitle: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'fullscreen',
    expectedIds: [
      for (var i = 1; i <= 10; i++) 'M8.$i',
      for (var i = 1; i <= 4; i++) 'M17.$i',
      for (var i = 1; i <= 4; i++) 'M18.$i',
    ],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 8: fullscreen controls stay while in use', () {
    testWidgets('M8.1 hide 3 s after the last movement while playing', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      await _elapse(tester, const Duration(milliseconds: 2500));
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      await _elapse(tester, const Duration(milliseconds: 1000));
      expect(_shown(tester, _dockOverlay), isFalse);
      expect(_shown(tester, _titleOverlay), isFalse);
      report.pass('M8.1');
    });

    testWidgets('M8.2 resting the mouse over the dock keeps the controls', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      final mouse = await _mouseAt(tester, _surfaceCenter);
      await mouse.moveTo(_dockCorner(tester));
      await tester.pump();
      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);

      await mouse.moveTo(_surfaceCenter);
      await tester.pump();
      await _elapse(tester, const Duration(milliseconds: 2500));
      expect(_shown(tester, _dockOverlay), isTrue);
      await _elapse(tester, const Duration(milliseconds: 1000));
      expect(_shown(tester, _dockOverlay), isFalse);
      report.pass('M8.2');
    });

    testWidgets('M8.3 a pointer held down in the dock keeps the controls', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      final touch = await tester.startGesture(
        _dockCorner(tester),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      await touch.up();
      await tester.pump();
      await _elapse(tester, const Duration(milliseconds: 2000));
      expect(_shown(tester, _dockOverlay), isTrue);
      await _elapse(tester, const Duration(milliseconds: 2500));
      expect(_shown(tester, _dockOverlay), isFalse);
      report.pass('M8.3');
    });

    testWidgets('M8.4 paused playback keeps the controls', (tester) async {
      final player = await _pumpPlayer(tester);
      await _enterFullscreen(tester);

      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      player.emitPlaying(true);
      await tester.pump();
      await _elapse(tester, const Duration(milliseconds: 4500));
      expect(_shown(tester, _dockOverlay), isFalse);

      player.emitPlaying(false);
      await tester.pump();
      expect(_shown(tester, _dockOverlay), isTrue);
      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);
      report.pass('M8.4');
    });

    testWidgets('M8.5 an open dialog keeps the controls', (tester) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      final context = tester.element(find.byType(PlayerScreen));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('probe dialog')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('probe dialog'), findsOneWidget);

      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('probe dialog'), findsNothing);
      expect(_shown(tester, _dockOverlay), isTrue);

      await _elapse(tester, const Duration(milliseconds: 4500));
      expect(_shown(tester, _dockOverlay), isFalse);
      report.pass('M8.5');
    });

    testWidgets('M8.6 the open queue drawer keeps the controls', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Play queue'), findsOneWidget);

      await _elapse(tester, const Duration(seconds: 10));
      expect(_shown(tester, _dockOverlay), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Play queue'), findsNothing);
      expect(PlayerScreenHarness.fullscreenCalls, [true]);

      await _elapse(tester, const Duration(milliseconds: 4500));
      expect(_shown(tester, _dockOverlay), isFalse);
      report.pass('M8.6');
    });

    testWidgets('M8.7 moving the mouse anywhere reveals hidden controls', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);
      final mouse = await _mouseAt(tester, _surfaceCenter);

      await _elapse(tester, const Duration(seconds: 4));
      expect(_shown(tester, _dockOverlay), isFalse);

      await mouse.moveTo(const Offset(900, 300));
      await tester.pump();
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(_shown(tester, _titleOverlay), isTrue);

      await _elapse(tester, const Duration(milliseconds: 2500));
      expect(_shown(tester, _dockOverlay), isTrue);
      await mouse.moveTo(const Offset(910, 310));
      await tester.pump();
      await _elapse(tester, const Duration(milliseconds: 2500));
      expect(_shown(tester, _dockOverlay), isTrue);
      await _elapse(tester, const Duration(milliseconds: 1000));
      expect(_shown(tester, _dockOverlay), isFalse);
      report.pass('M8.7');
    });

    testWidgets('M8.8 hidden overlays ignore pointer input', (tester) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);

      expect(_ignoring(tester, _dockOverlay), isFalse);
      expect(_ignoring(tester, _titleOverlay), isFalse);

      await _elapse(tester, const Duration(seconds: 4));
      expect(_ignoring(tester, _dockOverlay), isTrue);
      expect(_ignoring(tester, _titleOverlay), isTrue);
      report.pass('M8.8');
    });

    testWidgets('M8.9 shortcuts work with the controls hidden', (tester) async {
      final player = await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/song.mp3'),
      );
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);
      await _elapse(tester, const Duration(seconds: 4));
      expect(_shown(tester, _dockOverlay), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(player.playPauseInvocations, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(PlayerScreenHarness.fullscreenCalls, [true, false]);
      expect(find.byKey(_dockOverlay), findsNothing);
      expect(find.byType(PlayerBottomDock), findsOneWidget);
      report.pass('M8.9');
    });

    testWidgets('M8.10 the cursor hides with the controls', (tester) async {
      MouseCursor surfaceCursor() {
        final regions = tester.widgetList<MouseRegion>(
          find.descendant(
            of: find.byType(MediaSurface),
            matching: find.byType(MouseRegion),
          ),
        );
        return regions
            .map((region) => region.cursor)
            .firstWhere(
              (cursor) => cursor == SystemMouseCursors.none,
              orElse: () => MouseCursor.defer,
            );
      }

      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();

      expect(surfaceCursor(), MouseCursor.defer);
      await _enterFullscreen(tester);
      expect(surfaceCursor(), MouseCursor.defer);

      await _elapse(tester, const Duration(seconds: 4));
      expect(surfaceCursor(), SystemMouseCursors.none);

      final mouse = await _mouseAt(tester, _surfaceCenter);
      await mouse.moveTo(const Offset(820, 420));
      await tester.pump();
      expect(surfaceCursor(), MouseCursor.defer);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _elapse(tester, const Duration(seconds: 5));
      expect(surfaceCursor(), MouseCursor.defer);
      report.pass('M8.10');
    });
  });

  group('Finding 17: content switcher animates', () {
    testWidgets('M17.1 the switcher child is keyed by surface kind', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      await tester.pumpAndSettle();
      expect(_switcherChildKey(tester), const ValueKey('media-drop-zone'));
      expect(find.byKey(const ValueKey('media-drop-zone')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());

      final audio = await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/song.mp3'),
      );
      await tester.pumpAndSettle();
      expect(_switcherChildKey(tester), const ValueKey('media-audio'));
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);

      audio.emitTracks(_artTracks());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_switcherChildKey(tester), const ValueKey('media-audio-with-art'));
      expect(
        find.byKey(const ValueKey('media-audio-with-art')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPlayer(tester, source: PlayableSource.file('/media/clip.mp4'));
      await tester.pumpAndSettle();
      expect(_switcherChildKey(tester), const ValueKey('media-video'));
      expect(find.byKey(const ValueKey('media-video')), findsOneWidget);
      report.pass('M17.1');
    });

    testWidgets('M17.2 drop zone to a loaded source cross-fades', (
      tester,
    ) async {
      await _pumpPlayer(tester, source: PlayableSource.file('/media/song.mp3'));
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byKey(const ValueKey('media-drop-zone')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('media-drop-zone')), findsNothing);
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);
      report.pass('M17.2');
    });

    testWidgets('M17.3 loaded surface kinds cross-fade', (tester) async {
      final player = await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/song.mp3'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);

      player.emitTracks(_artTracks());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media-audio-with-art')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('media-audio')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/first.mp3'),
        playlist: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.mkv'),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second.mkv'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('media-audio')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-video')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('media-audio')), findsNothing);
      expect(find.byKey(const ValueKey('media-video')), findsOneWidget);
      report.pass('M17.3');
    });

    testWidgets('M17.4 taps and double taps work during and after a switch', (
      tester,
    ) async {
      final player = await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/song.mp3'),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('media-drop-zone')), findsOneWidget);

      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.playPauseInvocations, 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('media-drop-zone')), findsNothing);
      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.playPauseInvocations, 2);

      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(_surfaceCenter);
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.playPauseInvocations, 2);
      expect(PlayerScreenHarness.fullscreenCalls, [true]);
      report.pass('M17.4');
    });
  });

  group('Finding 18: fullscreen controls do not relayout the video', () {
    testWidgets('M18.1 surface geometry is identical shown and hidden', (
      tester,
    ) async {
      final player = await _pumpPlayer(
        tester,
        source: PlayableSource.file('/media/clip.mp4'),
      );
      player.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _enterFullscreen(tester);

      final surface = find.byType(MediaSurface);
      final window = tester.getRect(find.byType(Scaffold).first);
      final shown = tester.getRect(surface);
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(shown, window);

      await _elapse(tester, const Duration(seconds: 4));
      expect(_shown(tester, _dockOverlay), isFalse);
      expect(tester.getRect(surface), shown);

      final mouse = await _mouseAt(tester, _surfaceCenter);
      await mouse.moveTo(const Offset(840, 380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shown(tester, _dockOverlay), isTrue);
      expect(tester.getRect(surface), shown);
      report.pass('M18.1');
    });

    testWidgets('M18.2 the dock is an overlay inside the surface rect', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      await _enterFullscreen(tester);

      final surface = tester.getRect(find.byType(MediaSurface));
      final dock = tester.getRect(find.byType(PlayerBottomDock));
      expect(surface.contains(dock.topLeft), isTrue);
      expect(dock.bottom, closeTo(surface.bottom, 0.5));
      expect(dock.top, lessThan(surface.bottom));
      report.pass('M18.2');
    });

    testWidgets('M18.3 windowed layout keeps the column', (tester) async {
      await _pumpPlayer(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(_dockOverlay), findsNothing);
      expect(find.byKey(_titleOverlay), findsNothing);
      final surface = tester.getRect(find.byType(MediaSurface));
      final dock = tester.getRect(find.byType(PlayerBottomDock));
      final window = tester.getRect(find.byType(Scaffold).first);
      expect(surface.height, lessThan(window.height));
      expect(dock.top, greaterThanOrEqualTo(surface.bottom - 0.5));
      report.pass('M18.3');
    });

    testWidgets('M18.4 toggling fullscreen keeps the media surface mounted', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      await tester.pumpAndSettle();
      player.emitPlaying(true);
      await tester.pump();
      final before = tester.element(find.byType(MediaSurface));

      await _enterFullscreen(tester);
      expect(
        identical(tester.element(find.byType(MediaSurface)), before),
        true,
      );
      expect(before.mounted, isTrue);

      await _elapse(tester, const Duration(seconds: 4));
      expect(_shown(tester, _dockOverlay), isFalse);
      expect(
        identical(tester.element(find.byType(MediaSurface)), before),
        true,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(PlayerScreenHarness.fullscreenCalls, [true, false]);
      expect(
        identical(tester.element(find.byType(MediaSurface)), before),
        true,
      );
      report.pass('M18.4');
    });
  });
}
