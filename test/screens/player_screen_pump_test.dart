import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit/media_kit.dart';

import 'package:dacx/models/chapter_info.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/instance_mode_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/widgets/custom_title_bar.dart';
import 'package:dacx/widgets/compact_exit_button.dart';
import 'package:dacx/widgets/transport_controls.dart';

import '../support/player_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  testWidgets('pumps PlayerScreen shell without libmpv', (tester) async {
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CustomTitleBar), findsOneWidget);
    expect(find.byType(TransportControls), findsOneWidget);
  });

  testWidgets('shows drop zone when no media is loaded', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: HeadlessPlayerService(),
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Drop a file here'), findsOneWidget);
  });

  testWidgets('shows seek bar after duration stream event', (tester) async {
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
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('seek-visible')), findsNothing);

    player.emitDuration(const Duration(minutes: 3, seconds: 30));
    player.emitPosition(const Duration(seconds: 45));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('seek-visible')), findsOneWidget);
    expect(find.text('00:45'), findsOneWidget);
    expect(find.text('03:30'), findsOneWidget);
  });

  testWidgets('opens play queue drawer from transport controls', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Play queue'), findsOneWidget);
    expect(find.text('Queue is empty.'), findsOneWidget);
  });

  testWidgets('opens settings screen from transport controls', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('stop clears seeded media and hides seek bar', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitDuration(const Duration(minutes: 2));
    player.emitPosition(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('seek-visible')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-drop-zone')), findsNothing);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('seek-visible')), findsNothing);
    expect(find.textContaining('Drop a file here'), findsOneWidget);
  });

  testWidgets('play pause toggles transport icon when media is seeded', (
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitPlaying(true);
    await tester.pump();

    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('play queue drawer lists seeded playlist items', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        headlessMediaSurface: true,
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    expect(find.text('first.mp3'), findsOneWidget);
    expect(find.text('second.flac'), findsOneWidget);
    expect(find.text('Queue is empty.'), findsNothing);
  });

  testWidgets('queue item tap loads selected source in headless mode', (
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
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.map((c) => c.path), contains('/media/second.flac'));
    expect(find.bySemanticsLabel('Play: second.flac. Reorder'), findsOneWidget);
  });

  testWidgets('rapid queue taps keep the last selected item', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService()
      ..openDelay = const Duration(milliseconds: 60);

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
          PlayableSource.file('/media/third.mkv'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('second.flac'));
    await tester.tap(find.text('third.mkv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.map((c) => c.path), [
      '/media/second.flac',
      '/media/third.mkv',
    ]);
    expect(find.bySemanticsLabel('Play: third.mkv. Reorder'), findsOneWidget);
  });

  testWidgets('settings resume toggle persists from player navigation', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'dacx_player_settings_test_',
    );
    addTearDown(() {
      InstanceModeService.setFlagDirForTesting(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    InstanceModeService.setFlagDirForTesting(tempDir.path);

    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    expect(services.settings.resumePlaybackEnabled, isTrue);

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Resume from last position'));
    await tester.pumpAndSettle();

    expect(services.settings.resumePlaybackEnabled, isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(TransportControls), findsOneWidget);
  });

  testWidgets('space shortcut toggles play pause when media is loaded', (
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitPlaying(true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(player.playPauseInvocations, 1);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('space shortcut is ignored when no media is loaded', (
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(player.playPauseInvocations, 0);
  });

  testWidgets('arrow right shortcut seeks forward when duration is known', (
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitDuration(const Duration(minutes: 5));
    player.emitPosition(const Duration(minutes: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(find.text('01:05'), findsOneWidget);
  });

  testWidgets('m shortcut toggles mute and restores volume', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(services.settings.volume, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(services.settings.volume, 100);
  });

  testWidgets('arrow up shortcut increases volume', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_volume': 50.0},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(services.settings.volume, 55);
  });

  testWidgets('arrow down shortcut decreases volume', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_volume': 50.0},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(services.settings.volume, 45);
  });

  testWidgets('arrow left shortcut seeks backward when duration is known', (
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitDuration(const Duration(minutes: 5));
    player.emitPosition(const Duration(minutes: 1, seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget);
  });

  testWidgets('f shortcut requests fullscreen toggle', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(PlayerScreenHarness.fullscreenCalls, [true]);
  });

  testWidgets('ctrl arrow right shortcut steps to next chapter', (
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
        initialChapters: const [
          ChapterInfo(index: 0, title: 'Intro', time: Duration.zero),
          ChapterInfo(index: 1, title: 'Main', time: Duration(minutes: 5)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), '1');
    expect(find.text('Chapter: Main'), findsOneWidget);
  });

  testWidgets('shift n shortcut advances to next queue item', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.map((c) => c.path), contains('/media/second.flac'));
    expect(find.text('Next in queue'), findsOneWidget);
  });

  testWidgets('e shortcut toggles equalizer and shows osd', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(services.settings.eqEnabled, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    expect(services.settings.eqEnabled, isTrue);
    expect(find.text('Equalizer: On'), findsOneWidget);
  });

  testWidgets('a shortcut cycles to next audio track', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    const tracks = Tracks(
      audio: [
        AudioTrack('eng', 'English', null),
        AudioTrack('jpn', 'Japanese', null),
      ],
      video: [],
      subtitle: [],
    );

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitTracks(tracks);
    player.emitTrack(
      Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.audioTrackCalls.single.id, 'jpn');
    expect(find.textContaining('Japanese'), findsOneWidget);
  });

  testWidgets('j shortcut cycles to next subtitle track', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    const tracks = Tracks(
      audio: [AudioTrack('eng', 'English', null)],
      video: [],
      subtitle: [
        SubtitleTrack('eng', 'English', null),
        SubtitleTrack('spa', 'Spanish', null),
      ],
    );

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitTracks(tracks);
    player.emitTrack(
      Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.subtitleTrackCalls.single.id, 'eng');
    expect(find.textContaining('English'), findsOneWidget);
  });

  testWidgets('v shortcut toggles subtitle visibility', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    const tracks = Tracks(
      audio: [AudioTrack('eng', 'English', null)],
      video: [],
      subtitle: [SubtitleTrack('eng', 'English', null)],
    );

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitTracks(tracks);
    player.emitTrack(
      Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: const SubtitleTrack('eng', 'English', null),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();

    expect(player.subtitleTrackCalls.single.id, 'no');
    expect(find.text('Subtitles: Off'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();

    expect(player.subtitleTrackCalls.last.id, 'eng');
    expect(find.textContaining('English'), findsOneWidget);
  });

  testWidgets('shift p shortcut returns to previous queue item', (
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
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.last.path, '/media/first.mp3');
    expect(find.text('Previous in queue'), findsOneWidget);
  });

  testWidgets('queue tap shows snackbar when open fails in headless mode', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService()
      ..openError = Exception('decoder failed');

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Could not open'), findsOneWidget);
  });

  testWidgets(
    'ctrl s shortcut shows screenshot failed osd without frame data',
    (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      final osdProbe = ValueNotifier<String?>(null);
      final player = HeadlessPlayerService();

      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          playerService: player,
          headlessMediaSurface: true,
          initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
          osdMessageProbe: osdProbe,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Screenshot failed'), findsOneWidget);
      expect(osdProbe.value, 'Screenshot failed');
    },
  );

  testWidgets(
    'ctrl s shortcut saves screenshot bytes to configured directory',
    (tester) async {
      final screenshotDir = Directory.systemTemp.createTempSync(
        'dacx_screenshot_test_',
      );
      addTearDown(() {
        if (screenshotDir.existsSync()) {
          screenshotDir.deleteSync(recursive: true);
        }
      });

      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      final osdProbe = ValueNotifier<String?>(null);
      services.settings.screenshotDir = screenshotDir.path;
      expect(services.settings.screenshotDir, screenshotDir.path);
      final player = HeadlessPlayerService()
        ..screenshotResult = Uint8List.fromList(const [0xFF, 0xD8, 0xFF]);

      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          playerService: player,
          headlessMediaSurface: true,
          initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
          osdMessageProbe: osdProbe,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final savedFiles = screenshotDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList();
        if (savedFiles.isNotEmpty) break;
      }

      final savedFiles = screenshotDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(savedFiles, hasLength(1));
      expect(savedFiles.single.path, contains('movie'));
      expect(osdProbe.value, 'Screenshot saved');
      expect(find.text('Screenshot saved'), findsOneWidget);
    },
  );

  testWidgets('ctrl shift m shortcut enters compact mode', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Mini-player on'), findsOneWidget);
    expect(find.byType(CompactExitButton), findsOneWidget);
  });

  testWidgets('queue tap shows permission denied snackbar for access errors', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService()
      ..openError = Exception('open failed: Permission denied');

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Permission denied'), findsOneWidget);
  });

  testWidgets('escape shortcut exits fullscreen when active', (tester) async {
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(PlayerScreenHarness.fullscreenCalls, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(PlayerScreenHarness.fullscreenCalls, [true, false]);
  });

  testWidgets('single dropped path loads media in headless mode', (
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
        initialDropPaths: const ['/media/dropped.mp3'],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.map((c) => c.path), contains('/media/dropped.mp3'));
  });

  testWidgets('multiple dropped paths enqueue and open the first item', (
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
        initialDropPaths: const ['/media/first.mp3', '/media/second.flac'],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.single.path, '/media/first.mp3');
    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    expect(find.text('second.flac'), findsOneWidget);
  });

  testWidgets('queue load resets mix graph and honors autoplay setting', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_auto_play': false},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      player.propertyCalls.where((c) => c.name == 'lavfi-complex'),
      isNotEmpty,
    );
    expect(player.openCalls.last.play, isFalse);
  });

  testWidgets('pending invalid url load shows validation snackbar', (
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
        initialPendingLoad: PlayableSource.url('ftp://example.com/live'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls, isEmpty);
    expect(find.textContaining('valid http'), findsOneWidget);
  });

  testWidgets('pending empty file path shows invalid path snackbar', (
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
        initialPendingLoad: PlayableSource.file('   '),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls, isEmpty);
    expect(find.textContaining('Invalid file path'), findsOneWidget);
  });

  testWidgets('shift n wraps to first item when loop-all is enabled', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_loop_mode': 'loop'},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.last.path, '/media/first.mp3');
    expect(find.text('Next in queue'), findsOneWidget);
  });

  testWidgets('ctrl o shortcut opens file from picker', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final pickedFile = File(
      '${Directory.systemTemp.path}/dacx_ctrl_o_picked.mp3',
    )..writeAsStringSync('test');
    addTearDown(() {
      if (pickedFile.existsSync()) pickedFile.deleteSync();
    });
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    PlayerScreenHarness.filePickerPaths = [pickedFile.path];

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.map((c) => c.path), contains(pickedFile.path));
  });

  testWidgets('ctrl r shortcut reopens most recent file', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final recentFile = File(
      '${Directory.systemTemp.path}/dacx_ctrl_r_recent.mp3',
    )..writeAsStringSync('test');
    addTearDown(() {
      if (recentFile.existsSync()) recentFile.deleteSync();
    });
    final services = await PlayerScreenHarness.createServices(
      prefs: {
        'recent_files': jsonEncode([recentFile.path]),
      },
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.map((c) => c.path), contains(recentFile.path));
  });

  testWidgets('all invalid dropped paths show unreadable snackbar', (
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
        initialDropPaths: const ['', '   '],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls, isEmpty);
    expect(find.text('Could not read dropped file path.'), findsOneWidget);
  });

  testWidgets('shift p wraps to last item when loop-all is enabled', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_loop_mode': 'loop'},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('first.mp3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.last.path, '/media/second.flac');
    expect(find.text('Previous in queue'), findsOneWidget);
  });

  testWidgets('ctrl arrow left shortcut steps to previous chapter', (
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
        initialChapters: const [
          ChapterInfo(index: 0, title: 'Intro', time: Duration.zero),
          ChapterInfo(index: 1, title: 'Main', time: Duration(minutes: 5)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await player.setChapter(1);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), '0');
    expect(find.text('Chapter: Intro'), findsOneWidget);
  });

  testWidgets('a shortcut is ignored when only one audio track exists', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    const tracks = Tracks(
      audio: [AudioTrack('eng', 'English', null)],
      video: [],
      subtitle: [],
    );

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitTracks(tracks);
    player.emitTrack(
      Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.audioTrackCalls, isEmpty);
  });

  testWidgets('ctrl n shortcut requests a new window', (tester) async {
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
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      PlayerScreenHarness.windowMethodsCalls.map((c) => c.method),
      contains('openNewWindow'),
      skip: Platform.isMacOS ? false : 'macOS uses in-process window bridge',
    );
  });

  testWidgets('mixed dropped paths skip unreadable files and load the rest', (
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
        initialDropPaths: const ['   ', '/media/valid.mp3', ''],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.map((c) => c.path), contains('/media/valid.mp3'));
    expect(find.text('Skipped 2 unreadable files.'), findsOneWidget);
  });

  testWidgets('ctrl arrow left at first chapter stays on intro', (
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
        initialChapters: const [
          ChapterInfo(index: 0, title: 'Intro', time: Duration.zero),
          ChapterInfo(index: 1, title: 'Main', time: Duration(minutes: 5)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), '0');
    expect(find.text('Chapter: Intro'), findsOneWidget);
  });

  testWidgets('ctrl arrow right at last chapter stays on final chapter', (
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
        initialChapters: const [
          ChapterInfo(index: 0, title: 'Intro', time: Duration.zero),
          ChapterInfo(index: 1, title: 'Main', time: Duration(minutes: 5)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    await player.setChapter(1);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), '1');
    expect(find.text('Chapter: Main'), findsOneWidget);
  });

  testWidgets('ctrl r with no recents opens file picker', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final pickedFile = File(
      '${Directory.systemTemp.path}/dacx_ctrl_r_fallback.mp3',
    )..writeAsStringSync('test');
    addTearDown(() {
      if (pickedFile.existsSync()) pickedFile.deleteSync();
    });
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    PlayerScreenHarness.filePickerPaths = [pickedFile.path];

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.map((c) => c.path), contains(pickedFile.path));
  });

  testWidgets('j shortcut is ignored when no subtitle tracks exist', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    const tracks = Tracks(
      audio: [AudioTrack('eng', 'English', null)],
      video: [],
      subtitle: [],
    );

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    player.emitTracks(tracks);
    player.emitTrack(
      Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.subtitleTrackCalls, isEmpty);
  });

  testWidgets('ctrl r shortcut reopens most recent url', (tester) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    const recentUrl = 'https://example.com/live.m3u8';
    final services = await PlayerScreenHarness.createServices(
      prefs: {
        'recent_files': jsonEncode([recentUrl]),
      },
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(player.openCalls.map((c) => c.path), contains(recentUrl));
  });

  testWidgets('ctrl arrow shortcuts are ignored when no chapters exist', (
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
        initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), isNull);
    expect(find.textContaining('Chapter:'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await player.getProperty('chapter'), isNull);
    expect(find.textContaining('Chapter:'), findsNothing);
  });

  testWidgets('shift n does not advance past last item when loop is off', (
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
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second.flac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final opensBefore = player.openCalls.length;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.length, opensBefore);
    expect(find.text('Next in queue'), findsNothing);
  });

  testWidgets('shift p does not wrap before first item when loop is off', (
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
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('first.mp3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final opensBefore = player.openCalls.length;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.length, opensBefore);
    expect(find.text('Previous in queue'), findsNothing);
  });

  testWidgets(
    'shift n does not advance past last item when loop-single is enabled',
    (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices(
        prefs: {'playback_loop_mode': 'single'},
      );
      final player = HeadlessPlayerService();

      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          playerService: player,
          headlessMediaSurface: true,
          initialPlaylistSources: [
            PlayableSource.file('/media/first.mp3'),
            PlayableSource.file('/media/second.flac'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second.flac'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final opensBefore = player.openCalls.length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.openCalls.length, opensBefore);
      expect(find.text('Next in queue'), findsNothing);
    },
  );

  testWidgets(
    'shift p does not wrap before first item when loop-single is enabled',
    (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices(
        prefs: {'playback_loop_mode': 'single'},
      );
      final player = HeadlessPlayerService();

      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          playerService: player,
          headlessMediaSurface: true,
          initialPlaylistSources: [
            PlayableSource.file('/media/first.mp3'),
            PlayableSource.file('/media/second.flac'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first.mp3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final opensBefore = player.openCalls.length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.openCalls.length, opensBefore);
      expect(find.text('Previous in queue'), findsNothing);
    },
  );

  testWidgets('f1 shortcut opens keyboard shortcuts dialog', (tester) async {
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
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Open file'), findsOneWidget);
  });

  testWidgets('shift slash shortcut opens keyboard shortcuts dialog', (
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
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testWidgets('ctrl r prunes missing recent file before reopen fallback', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final pickedFile = File(
      '${Directory.systemTemp.path}/dacx_ctrl_r_prune_fallback.mp3',
    )..writeAsStringSync('test');
    addTearDown(() {
      if (pickedFile.existsSync()) pickedFile.deleteSync();
    });
    final services = await PlayerScreenHarness.createServices(
      prefs: {
        'recent_files': jsonEncode(['/missing/recent.mp3']),
      },
    );
    final player = HeadlessPlayerService();
    PlayerScreenHarness.filePickerPaths = [pickedFile.path];

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      services.settings.recentFiles,
      isNot(contains('/missing/recent.mp3')),
    );
    expect(services.settings.recentFiles, contains(pickedFile.path));
    expect(player.openCalls.map((c) => c.path), contains(pickedFile.path));
  });

  testWidgets('playback completed does not advance queue in single loop mode', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_loop_mode': 'single'},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/media/first.mp3'),
        initialPlaylistSources: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.flac'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(player.playlistModeCalls, contains(PlaylistMode.single));

    final opensBefore = player.openCalls.length;
    player.emitCompleted(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.openCalls.length, opensBefore);
    expect(find.text('Next in queue'), findsNothing);
  });

  testWidgets('single loop mode applies playlist single to player', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices(
      prefs: {'playback_loop_mode': 'single'},
    );
    final player = HeadlessPlayerService();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.playlistModeCalls, contains(PlaylistMode.single));
  });

  testWidgets('media session loop command enables single repeat mode', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    final mediaCommands = StreamController<MediaSessionCommand>.broadcast();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
        mediaSessionCommandsForTesting: mediaCommands,
      ),
    );
    await tester.pump();
    await tester.pump();

    mediaCommands.add(const MediaSessionCommand('loop', null, value: 0.5));
    await tester.pump();
    await tester.pump();

    expect(services.settings.loopMode, LoopMode.single);
    expect(player.playlistModeCalls.last, PlaylistMode.single);
    await mediaCommands.close();
  });

  testWidgets(
    'media session next does not advance past last item in single loop mode',
    (tester) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices(
        prefs: {'playback_loop_mode': 'single'},
      );
      final player = HeadlessPlayerService();
      final mediaCommands = StreamController<MediaSessionCommand>.broadcast();

      await tester.pumpWidget(
        PlayerScreenHarness.wrap(
          settings: services.settings,
          debugLog: services.debugLog,
          updates: services.updates,
          playerService: player,
          headlessMediaSurface: true,
          mediaSessionCommandsForTesting: mediaCommands,
          initialPlaylistSources: [
            PlayableSource.file('/media/first.mp3'),
            PlayableSource.file('/media/second.flac'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Play Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second.flac'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final opensBefore = player.openCalls.length;

      mediaCommands.add(const MediaSessionCommand('next', null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.openCalls.length, opensBefore);
      expect(find.text('Next in queue'), findsNothing);
      await mediaCommands.close();
    },
  );

  testWidgets('media session shuffle command enables playlist shuffle', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    final mediaCommands = StreamController<MediaSessionCommand>.broadcast();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
        mediaSessionCommandsForTesting: mediaCommands,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(services.settings.playlistShuffle, isFalse);

    mediaCommands.add(const MediaSessionCommand('shuffle', null, value: 1.0));
    await tester.pump();
    await tester.pump();

    expect(services.settings.playlistShuffle, isTrue);
    await mediaCommands.close();
  });

  testWidgets('media session volume command updates settings and player', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    final mediaCommands = StreamController<MediaSessionCommand>.broadcast();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
        mediaSessionCommandsForTesting: mediaCommands,
      ),
    );
    await tester.pump();
    await tester.pump();

    mediaCommands.add(const MediaSessionCommand('volume', null, value: 0.5));
    await tester.pump();
    await tester.pump();

    expect(services.settings.volume, 50.0);
    await mediaCommands.close();
  });

  testWidgets('media session rate command updates playback speed setting', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    final player = HeadlessPlayerService();
    final mediaCommands = StreamController<MediaSessionCommand>.broadcast();

    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialLoadedSource: PlayableSource.file('/test/song.mp3'),
        mediaSessionCommandsForTesting: mediaCommands,
      ),
    );
    await tester.pump();
    await tester.pump();

    mediaCommands.add(const MediaSessionCommand('rate', null, value: 1.5));
    await tester.pump();
    await tester.pump();

    expect(services.settings.speed, 1.5);
    await mediaCommands.close();
  });
}
