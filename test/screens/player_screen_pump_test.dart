import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit/media_kit.dart';

import 'package:dacx/models/chapter_info.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/instance_mode_service.dart';
import 'package:dacx/widgets/custom_title_bar.dart';
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
    expect(find.bySemanticsLabel('Play: second.flac'), findsOneWidget);
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
    expect(find.bySemanticsLabel('Play: third.mkv'), findsOneWidget);
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
}
