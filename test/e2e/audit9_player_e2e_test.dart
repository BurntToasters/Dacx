import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/m3u_playlist.dart';
import 'package:dacx/playback/player_path_utils.dart';
import 'package:dacx/playback/screenshot_saver.dart';
import 'package:dacx/playback/volume_policy.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/widgets/compact_exit_button.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _nextTrackTooltip = 'Next Track (Shift+N)';
const _openFailedMessage = 'Could not open file. Try another file.';
const _mediaCenter = Offset(800, 400);

class _TaggedPlayer extends HeadlessPlayerService {
  final Map<String, Map<String, String>> tags = {};
  final Map<String, Completer<void>> titleGates = {};
  final Map<String, int> metadataReads = {};

  @override
  Future<String?> getProperty(String name) async {
    const prefix = 'metadata/by-key/';
    if (!name.startsWith(prefix)) return super.getProperty(name);
    metadataReads[name] = (metadataReads[name] ?? 0) + 1;
    final path = await super.getProperty('path');
    final key = name.substring(prefix.length);
    if (key == 'title') {
      final gate = titleGates[path];
      if (gate != null) await gate.future;
    }
    return tags[path]?[key];
  }
}

class _WindowMock {
  Size size = const Size(1200, 800);
  Offset position = const Offset(40, 60);
  bool maximized = false;
  Completer<void>? getBoundsGate;
  bool Function(Map<Object?, Object?> args)? failSetBounds;
  final List<MethodCall> calls = <MethodCall>[];

  int count(String method) => calls.where((c) => c.method == method).length;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PlayerScreenHarness.windowManagerChannel,
          handle,
        );
  }

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'isMaximized':
        return maximized;
      case 'isMinimized':
      case 'isFullScreen':
        return false;
      case 'getBounds':
        final gate = getBoundsGate;
        if (gate != null) await gate.future;
        return {
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        };
      case 'setBounds':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final fail = failSetBounds;
        if (fail != null && fail(args)) {
          throw PlatformException(code: 'set_bounds_failed');
        }
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

final class _ThrowingFilePicker extends FilePickerPlatform {
  _ThrowingFilePicker(this.error);

  final Object error;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    throw error;
  }
}

Future<({SettingsService settings, HeadlessPlayerService player})> pumpPlayer(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  HeadlessPlayerService? player,
  PlayableSource? loaded,
  List<PlayableSource>? playlist,
  List<String>? drops,
  PlayableSource? pending,
  ValueNotifier<String?>? osd,
  void Function(SettingsService settings)? prepare,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices(prefs: prefs);
  prepare?.call(services.settings);
  final service = player ?? HeadlessPlayerService();
  await tester.pumpWidget(
    PlayerScreenHarness.wrap(
      settings: services.settings,
      debugLog: services.debugLog,
      updates: services.updates,
      playerService: service,
      headlessMediaSurface: true,
      initialLoadedSource: loaded,
      initialPlaylistSources: playlist,
      initialDropPaths: drops,
      initialPendingLoad: pending,
      osdMessageProbe: osd,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (settings: services.settings, player: service);
}

Future<void> settle(WidgetTester tester, {int steps = 6}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> pressMiniPlayerShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> openQueueDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Play Queue'));
  await tester.pumpAndSettle();
}

Future<void> tapAddFiles(WidgetTester tester) async {
  await tester.tap(find.text('Add files…'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<List<String>> collectSnackTexts(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 14),
}) async {
  final seen = <String>[];
  var elapsed = Duration.zero;
  const step = Duration(milliseconds: 250);
  while (elapsed <= total) {
    final texts = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Text),
    );
    for (final element in texts.evaluate()) {
      final data = (element.widget as Text).data;
      if (data != null && !seen.contains(data)) seen.add(data);
    }
    await tester.pump(step);
    elapsed += step;
  }
  return seen;
}

Directory makeTempDir() {
  final dir = Directory.systemTemp.createTempSync('dacx_a9_player_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Future<void> scrollSurface(
  WidgetTester tester,
  double dy,
  Duration timestamp,
) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      timeStamp: timestamp,
      position: _mediaCenter,
      scrollDelta: Offset(0, dy),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'player',
    expectedIds: [
      'M1.1',
      'M1.2',
      'M1.3',
      'M1.4',
      'M1.5',
      'M1.6',
      'M1.7',
      'M2.1',
      'M2.2',
      'M2.3',
      'M2.4',
      'M2.5',
      'M2.6',
      'M2.7',
      'M4.1',
      'M4.2',
      'M4.3',
      'M4.4',
      'M4.5',
      'M5.1',
      'M5.2',
      'M5.3',
      'M5.4',
      'M5.5',
      'M9.1',
      'M9.2',
      'M9.3',
      'M9.4',
      'M9.5',
      'M9.6',
      'M9.7',
      'M15.3',
      'M15.4',
      'M15.5',
      'M15.6',
      'M16.1',
      'M16.2',
      'M16.3',
    ],
  );
  tearDownAll(report.write);

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  group('Finding 1: enqueue picker', () {
    testWidgets(
      'M1.1 requests custom type with audio and playlist extensions',
      (tester) async {
        await pumpPlayer(tester);
        await openQueueDrawer(tester);
        await tapAddFiles(tester);

        final call = PlayerScreenHarness.filePickerCalls.lastWhere(
          (c) => c.kind == 'pickFiles',
        );
        expect(call.type, FileType.custom);
        final allowed = call.allowedExtensions;
        expect(allowed, isNotNull);
        for (final ext in PlayerPathUtils.supportedExtensions) {
          expect(allowed, contains(ext), reason: 'missing $ext');
        }
        expect(allowed, containsAll(PlayerPathUtils.audioExtensions));
        expect(allowed, containsAll(M3uPlaylist.extensions));
        report.pass('M1.1');
      },
    );

    testWidgets('M1.2 passes an existing last open directory', (tester) async {
      final dir = makeTempDir();
      await pumpPlayer(
        tester,
        prepare: (settings) => settings.lastOpenDirectory = dir.path,
      );
      await openQueueDrawer(tester);
      await tapAddFiles(tester);

      final call = PlayerScreenHarness.filePickerCalls.lastWhere(
        (c) => c.kind == 'pickFiles',
      );
      expect(call.initialDirectory, dir.path);
      report.pass('M1.2');
    });

    testWidgets('M1.3 remembers the directory of the picked file', (
      tester,
    ) async {
      PlayerScreenHarness.filePickerPaths = ['/music/albums/song.flac'];
      final env = await pumpPlayer(
        tester,
        loaded: PlayableSource.file('/media/first.mp3'),
        playlist: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file('/media/second.mp3'),
        ],
      );
      expect(env.settings.lastOpenDirectory, isNull);
      await openQueueDrawer(tester);
      await tapAddFiles(tester);

      expect(
        env.settings.lastOpenDirectory,
        p.dirname('/music/albums/song.flac'),
      );
      report.pass('M1.3');
    });

    testWidgets('M1.4 a picked audio file reaches the player', (tester) async {
      PlayerScreenHarness.filePickerPaths = ['/music/albums/song.flac'];
      final env = await pumpPlayer(tester);
      await openQueueDrawer(tester);
      await tapAddFiles(tester);
      await settle(tester);

      expect(env.player.openCalls.map((c) => c.path), [
        '/music/albums/song.flac',
      ]);
      report.pass('M1.4');
    });

    testWidgets('M1.5 platform exception shows the picker failure snackbar', (
      tester,
    ) async {
      await pumpPlayer(tester);
      FilePickerPlatform.instance = _ThrowingFilePicker(
        PlatformException(code: 'denied', message: 'boom'),
      );
      await openQueueDrawer(tester);
      await tapAddFiles(tester);

      expect(find.text('File picker failed. boom'), findsOneWidget);
      report.pass('M1.5');
    });

    testWidgets('M1.6 other errors show the unable to open snackbar', (
      tester,
    ) async {
      await pumpPlayer(tester);
      FilePickerPlatform.instance = _ThrowingFilePicker(StateError('nope'));
      await openQueueDrawer(tester);
      await tapAddFiles(tester);

      expect(find.text('Unable to open file picker.'), findsOneWidget);
      report.pass('M1.6');
    });

    testWidgets('M1.7 cancelling shows nothing and changes nothing', (
      tester,
    ) async {
      PlayerScreenHarness.filePickerPaths = const [];
      final env = await pumpPlayer(tester);
      await openQueueDrawer(tester);
      await tapAddFiles(tester);
      await settle(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(env.player.openCalls, isEmpty);
      expect(env.settings.lastOpenDirectory, isNull);
      report.pass('M1.7');
    });
  });

  group('Finding 2: display metadata', () {
    const trackA = '/media/a.mp3';
    const trackB = '/media/b.mp3';

    _TaggedPlayer taggedPlayer() {
      final player = _TaggedPlayer();
      player.tags[trackA] = {'title': 'Track A', 'artist': 'Artist A'};
      player.tags[trackB] = {'title': 'Track B', 'artist': 'Artist B'};
      return player;
    }

    testWidgets('M2.1 tag title and artist show with the session off', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        prefs: {'media_session_enabled': false},
        player: taggedPlayer(),
        pending: PlayableSource.file(trackA),
      );
      await settle(tester);

      expect(find.text('Track A'), findsWidgets);
      expect(find.text('Artist A'), findsOneWidget);
      report.pass('M2.1');
    });

    testWidgets('M2.2 title falls back to the display name without a tag', (
      tester,
    ) async {
      final player = _TaggedPlayer();
      await pumpPlayer(
        tester,
        prefs: {'media_session_enabled': false},
        player: player,
        pending: PlayableSource.file(trackA),
      );
      await settle(tester);

      expect(find.text('a.mp3'), findsWidgets);
      expect(find.text('Artist A'), findsNothing);
      report.pass('M2.2');
    });

    testWidgets('M2.3 the OS bridge only receives metadata when enabled', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlayerScreenHarness.mediaSessionChannel, (
            call,
          ) async {
            calls.add(call);
            return null;
          });

      await pumpPlayer(
        tester,
        prefs: {'media_session_enabled': false},
        player: taggedPlayer(),
        pending: PlayableSource.file(trackA),
      );
      await settle(tester);
      expect(calls.where((c) => c.method == 'update'), isEmpty);
      expect(find.text('Artist A'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      calls.clear();
      await pumpPlayer(
        tester,
        player: taggedPlayer(),
        pending: PlayableSource.file(trackA),
      );
      await settle(tester);
      expect(find.text('Artist A'), findsOneWidget);
      if (!Platform.isLinux) {
        final updates = calls.where((c) => c.method == 'update').toList();
        expect(updates, isNotEmpty);
        final args = updates.last.arguments as Map<Object?, Object?>;
        expect(args['title'], 'Track A');
        expect(args['artist'], 'Artist A');
      }
      report.pass('M2.3');
    });

    testWidgets('M2.4 previous metadata disappears while the next is pending', (
      tester,
    ) async {
      final player = taggedPlayer();
      await pumpPlayer(tester, player: player, drops: [trackA, trackB]);
      await settle(tester);
      expect(find.text('Artist A'), findsOneWidget);

      player.titleGates[trackB] = Completer<void>();
      await tester.tap(find.byTooltip(_nextTrackTooltip));
      await settle(tester);
      expect(player.openCalls.last.path, trackB);
      expect(find.text('Artist A'), findsNothing);
      expect(find.text('Track A'), findsNothing);
      expect(find.text('Artist B'), findsNothing);

      player.titleGates[trackB]!.complete();
      await settle(tester);
      expect(find.text('Artist B'), findsOneWidget);
      expect(find.text('Track B'), findsWidgets);
      report.pass('M2.4');
    });

    testWidgets('M2.5 metadata resolving after a newer load is dropped', (
      tester,
    ) async {
      final player = taggedPlayer();
      player.titleGates[trackA] = Completer<void>();
      await pumpPlayer(tester, player: player, drops: [trackA, trackB]);
      await settle(tester);
      expect(player.openCalls.first.path, trackA);

      await tester.tap(find.byTooltip(_nextTrackTooltip));
      await settle(tester);
      expect(player.openCalls.last.path, trackB);
      expect(find.text('Artist B'), findsOneWidget);

      player.titleGates[trackA]!.complete();
      await settle(tester);
      expect(find.text('Track A'), findsNothing);
      expect(find.text('Artist A'), findsNothing);
      expect(find.text('Artist B'), findsOneWidget);
      report.pass('M2.5');
    });

    testWidgets('M2.6 stop does not leak the old artist into the next load', (
      tester,
    ) async {
      final player = taggedPlayer();
      await pumpPlayer(tester, player: player, drops: [trackA, trackB]);
      await settle(tester);
      expect(find.text('Artist A'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop'));
      await settle(tester);
      expect(find.text('Artist A'), findsNothing);

      player.titleGates[trackB] = Completer<void>();
      await openQueueDrawer(tester);
      await tester.tap(find.text('b.mp3'));
      await settle(tester);
      expect(player.openCalls.last.path, trackB);
      expect(find.text('Artist A'), findsNothing);
      expect(find.text('Track A'), findsNothing);

      player.titleGates[trackB]!.complete();
      await settle(tester);
      report.pass('M2.6');
    });

    testWidgets('M2.7 one load reads each metadata key once', (tester) async {
      final player = taggedPlayer();
      await pumpPlayer(
        tester,
        player: player,
        pending: PlayableSource.file(trackA),
      );
      await settle(tester);

      expect(player.metadataReads['metadata/by-key/title'], 1);
      expect(player.metadataReads['metadata/by-key/artist'], 1);
      report.pass('M2.7');
    });
  });

  group('Finding 4: mini-player toggle', () {
    final movie = PlayableSource.file('/test/movie.mkv');

    testWidgets('M4.1 a second toggle while the first runs is ignored', (
      tester,
    ) async {
      final win = _WindowMock()..install();
      await pumpPlayer(tester, loaded: movie);

      win.getBoundsGate = Completer<void>();
      await pressMiniPlayerShortcut(tester);
      final afterFirst = win.count('getBounds');
      expect(afterFirst, greaterThan(0));

      await pressMiniPlayerShortcut(tester);
      expect(win.count('getBounds'), afterFirst);

      win.getBoundsGate!.complete();
      win.getBoundsGate = null;
      await settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(win.size, const Size(480, 320));

      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      expect(win.size, const Size(1200, 800));
      report.pass('M4.1');
    });

    testWidgets('M4.2 a failed resize does not enable mini mode', (
      tester,
    ) async {
      final win = _WindowMock()..install();
      await pumpPlayer(tester, loaded: movie);

      win.failSetBounds = (args) =>
          args['width'] == 480 && args['height'] == 320;
      await pressMiniPlayerShortcut(tester);
      await settle(tester);

      expect(find.byType(CompactExitButton), findsNothing);
      expect(find.text('Mini-player on'), findsNothing);
      report.pass('M4.2');
    });

    testWidgets('M4.3 a toggle after a failed entry works', (tester) async {
      final win = _WindowMock()..install();
      await pumpPlayer(tester, loaded: movie);

      win.failSetBounds = (args) =>
          args['width'] == 480 && args['height'] == 320;
      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);

      win.failSetBounds = null;
      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(find.text('Mini-player on'), findsOneWidget);
      report.pass('M4.3');
    });

    testWidgets('M4.4 a failed restore keeps mini mode', (tester) async {
      final win = _WindowMock()..install();
      await pumpPlayer(tester, loaded: movie);

      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);

      win.failSetBounds = (_) => true;
      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);
      expect(find.text('Mini-player off'), findsNothing);

      win.failSetBounds = null;
      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      report.pass('M4.4');
    });

    testWidgets('M4.5 exit restores the current always-on-top setting', (
      tester,
    ) async {
      final win = _WindowMock()..install();
      final env = await pumpPlayer(
        tester,
        loaded: movie,
        prepare: (settings) => settings.alwaysOnTop = true,
      );

      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsOneWidget);

      env.settings.alwaysOnTop = false;
      await settle(tester);
      final mark = win.calls.length;

      await pressMiniPlayerShortcut(tester);
      await settle(tester);
      expect(find.byType(CompactExitButton), findsNothing);

      final restored = win.calls
          .skip(mark)
          .where((c) => c.method == 'setAlwaysOnTop')
          .toList();
      expect(restored, isNotEmpty);
      final args = restored.last.arguments as Map<Object?, Object?>;
      expect(args['isAlwaysOnTop'], isFalse);
      report.pass('M4.5');
    });
  });

  group('Finding 5: batch load failures', () {
    List<String> batch(int count) => [
      for (var i = 1; i <= count; i++) '/media/track$i.mp3',
    ];

    testWidgets('M5.1 many failures show one summary', (tester) async {
      final paths = batch(10);
      final player = HeadlessPlayerService()..failOpenPaths(paths);
      await pumpPlayer(tester, player: player, drops: paths);

      final texts = await collectSnackTexts(tester);
      expect(texts, ['10 files could not be opened']);
      expect(player.openCalls, isEmpty);
      report.pass('M5.1');
    });

    testWidgets('M5.2 summary counts failures before the first success', (
      tester,
    ) async {
      final paths = batch(6);
      final player = HeadlessPlayerService()..failOpenPaths(paths.take(5));
      await pumpPlayer(tester, player: player, drops: paths);

      final texts = await collectSnackTexts(tester);
      expect(texts, ['5 files could not be opened']);
      expect(player.openCalls.single.path, paths.last);
      report.pass('M5.2');
    });

    testWidgets('M5.3 one failure in a batch keeps the specific message', (
      tester,
    ) async {
      final paths = batch(2);
      final player = HeadlessPlayerService()..failOpenPaths([paths.first]);
      await pumpPlayer(tester, player: player, drops: paths);

      final texts = await collectSnackTexts(tester);
      expect(texts, [_openFailedMessage]);
      expect(player.openCalls.single.path, paths.last);
      report.pass('M5.3');
    });

    testWidgets('M5.4 a single-file failure keeps the specific message', (
      tester,
    ) async {
      final player = HeadlessPlayerService()..failOpenPaths(['/media/bad.mp3']);
      await pumpPlayer(
        tester,
        player: player,
        pending: PlayableSource.file('/media/bad.mp3'),
      );

      final texts = await collectSnackTexts(tester);
      expect(texts, [_openFailedMessage]);
      report.pass('M5.4');
    });

    test('M5.5 the summary is a plural localized string', () {
      final arb = jsonDecode(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final key = arb.keys.firstWhere(
        (k) =>
            !k.startsWith('@') &&
            arb[k] is String &&
            (arb[k] as String).contains('could not be opened') &&
            (arb[k] as String).contains('plural'),
        orElse: () => '',
      );
      expect(key, isNotEmpty);
      final message = arb[key] as String;
      expect(message, contains('{count, plural,'));
      expect(message, contains('=1{1 file could not be opened}'));
      expect(message, contains('other{{count} files could not be opened}'));
      final meta = arb['@$key'] as Map<String, dynamic>;
      final placeholders = meta['placeholders'] as Map<String, dynamic>;
      expect((placeholders['count'] as Map<String, dynamic>)['type'], 'int');
      report.pass('M5.5');
    });
  });

  group('Finding 9: scroll volume', () {
    const ms = Duration(milliseconds: 1);

    test('M9.1 a notch-sized event emits exactly one step', () {
      expect(ScrollVolumeAccumulator().add(-53, Duration.zero), 5);
      expect(ScrollVolumeAccumulator().add(53, Duration.zero), -5);
      expect(ScrollVolumeAccumulator().add(-100, Duration.zero), 5);
      expect(ScrollVolumeAccumulator().add(100, Duration.zero), -5);
      expect(ScrollVolumeAccumulator().add(-300, Duration.zero), 5);
      expect(ScrollVolumeAccumulator().add(50, Duration.zero), -5);
      expect(ScrollVolumeAccumulator().add(49, Duration.zero), 0);
      report.pass('M9.1');
    });

    test('M9.2 small deltas accumulate to one step per notch', () {
      final acc = ScrollVolumeAccumulator();
      for (var i = 0; i < 4; i++) {
        expect(acc.add(-12, ms * (i * 10)), 0);
      }
      expect(acc.add(-12, ms * 40), 5);
      expect(acc.add(-12, ms * 50), 0);
      var total = 0.0;
      for (var i = 1; i <= 4; i++) {
        total += acc.add(-12, ms * (50 + i * 10));
      }
      expect(total, 5);
      report.pass('M9.2');
    });

    test('M9.3 a direction flip discards the accumulated delta', () {
      final acc = ScrollVolumeAccumulator();
      expect(acc.add(-30, Duration.zero), 0);
      expect(acc.add(30, ms * 10), 0);
      expect(acc.add(30, ms * 20), -5);
      report.pass('M9.3');
    });

    test('M9.4 an idle gap of 200 ms discards the accumulated delta', () {
      final reset = ScrollVolumeAccumulator();
      expect(reset.add(-30, Duration.zero), 0);
      expect(reset.add(-30, ms * 200), 0);
      expect(reset.add(-30, ms * 250), 5);

      final kept = ScrollVolumeAccumulator();
      expect(kept.add(-30, Duration.zero), 0);
      expect(kept.add(-30, ms * 199), 5);
      report.pass('M9.4');
    });

    test('M9.5 zero deltas emit nothing and leave state alone', () {
      final acc = ScrollVolumeAccumulator();
      expect(acc.add(0, Duration.zero), 0);
      expect(acc.add(-30, ms * 10), 0);
      expect(acc.add(0, ms * 1000), 0);
      expect(acc.add(-30, ms * 110), 5);
      report.pass('M9.5');
    });

    testWidgets('M9.6 a wheel notch is one step and trackpad noise is not', (
      tester,
    ) async {
      final env = await pumpPlayer(
        tester,
        loaded: PlayableSource.file('/test/movie.mkv'),
        prepare: (settings) => settings.volume = 50,
      );

      await scrollSurface(tester, -100, Duration.zero);
      expect(env.settings.volume, 55);

      await scrollSurface(tester, -53, const Duration(seconds: 1));
      expect(env.settings.volume, 60);

      for (var i = 0; i < 15; i++) {
        await scrollSurface(
          tester,
          3,
          Duration(seconds: 2, milliseconds: i * 10),
        );
      }
      expect(env.settings.volume, 60);
      await tester.pump(const Duration(seconds: 1));
      report.pass('M9.6');
    });

    testWidgets('M9.7 scrolling stays clamped to 0..100', (tester) async {
      final env = await pumpPlayer(
        tester,
        loaded: PlayableSource.file('/test/movie.mkv'),
        prepare: (settings) => settings.volume = 98,
      );

      await scrollSurface(tester, -100, Duration.zero);
      expect(env.settings.volume, 100);

      env.settings.volume = 2;
      await tester.pump();
      await scrollSurface(tester, 100, const Duration(seconds: 1));
      expect(env.settings.volume, 0);
      await tester.pump(const Duration(seconds: 1));
      report.pass('M9.7');
    });
  });

  group('Finding 15: filesystem checks at use', () {
    Future<List<String?>> pickerDirectories(
      WidgetTester tester,
      String? lastOpen,
    ) async {
      PlayerScreenHarness.filePickerCalls.clear();
      await pumpPlayer(
        tester,
        prepare: (settings) => settings.lastOpenDirectory = lastOpen,
      );
      await pressCtrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);
      await openQueueDrawer(tester);
      await tester.tap(find.byKey(const Key('queue-add-folder-button')));
      await settle(tester);
      await tapAddFiles(tester);
      await settle(tester);
      String? directoryOf(String kind) => PlayerScreenHarness.filePickerCalls
          .lastWhere((c) => c.kind == kind)
          .initialDirectory;
      final result = [
        directoryOf('pickFile'),
        directoryOf('getDirectoryPath'),
        directoryOf('pickFiles'),
      ];
      await tester.pumpWidget(const SizedBox.shrink());
      return result;
    }

    testWidgets('M15.3 pickers use the stored directory only if it exists', (
      tester,
    ) async {
      final base = makeTempDir();
      final existing = Directory(p.join(base.path, 'existing'))..createSync();
      final missing = p.join(base.path, 'missing');

      expect(await pickerDirectories(tester, existing.path), [
        existing.path,
        existing.path,
        existing.path,
      ]);
      expect(await pickerDirectories(tester, missing), [null, null, null]);
      report.pass('M15.3');
    });

    Future<ValueNotifier<String?>> takeScreenshot(
      WidgetTester tester,
      String screenshotDir,
    ) async {
      final osd = ValueNotifier<String?>(null);
      final player = HeadlessPlayerService()
        ..screenshotResult = Uint8List.fromList(const [0xFF, 0xD8, 0xFF]);
      await pumpPlayer(
        tester,
        player: player,
        loaded: PlayableSource.file('/test/a9_shot_clip.mkv'),
        osd: osd,
        prepare: (settings) => settings.screenshotDir = screenshotDir,
      );
      await pressCtrl(tester, LogicalKeyboardKey.keyS);
      for (var i = 0; i < 30 && osd.value != 'Screenshot saved'; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return osd;
    }

    testWidgets('M15.4 a missing screenshot directory falls back to default', (
      tester,
    ) async {
      final base = makeTempDir();
      final missing = Directory(p.join(base.path, 'missing'));
      final defaultDir = Directory(p.join(base.path, 'default'));
      ScreenshotSaver.defaultDirectoryOverride = () => defaultDir.path;
      addTearDown(() => ScreenshotSaver.defaultDirectoryOverride = null);

      final osd = await takeScreenshot(tester, missing.path);

      expect(missing.existsSync(), isFalse);
      expect(osd.value, 'Screenshot saved');
      final created = defaultDir
          .listSync()
          .where((e) => p.basename(e.path).contains('a9_shot_clip'))
          .toList();
      expect(created, hasLength(1));
      report.pass('M15.4');
    });

    testWidgets('M15.5 an existing screenshot directory is still used', (
      tester,
    ) async {
      final dir = makeTempDir();

      final osd = await takeScreenshot(tester, dir.path);

      expect(osd.value, 'Screenshot saved');
      final saved = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('a9_shot_clip'))
          .toList();
      expect(saved, hasLength(1));
      report.pass('M15.5');
    });

    test('M15.6 no picker receives lastOpenDirectory unchecked', () {
      final source = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(
        RegExp(r'initialDirectory:\s*_settings\.lastOpenDirectory')
            .hasMatch(source),
        isFalse,
      );
      report.pass('M15.6');
    });
  });

  group('Finding 16: click to pause', () {
    final movie = PlayableSource.file('/test/movie.mkv');

    testWidgets('M16.1 a click toggles playback after the double-tap wait', (
      tester,
    ) async {
      final env = await pumpPlayer(tester, loaded: movie);

      await tester.tapAt(_mediaCenter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      expect(env.player.playPauseInvocations, 1);

      await tester.pump(const Duration(milliseconds: 400));
      expect(env.player.playPauseInvocations, 1);
      report.pass('M16.1');
    });

    testWidgets('M16.2 a double click toggles fullscreen only', (tester) async {
      final env = await pumpPlayer(tester, loaded: movie);

      await tester.tapAt(_mediaCenter);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_mediaCenter);
      await tester.pump(const Duration(milliseconds: 600));

      expect(PlayerScreenHarness.fullscreenCalls, contains(true));
      expect(env.player.playPauseInvocations, 0);
      report.pass('M16.2');
    });

    test('M16.3 the media surface owns no tap timer', () {
      final source = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(source, isNot(contains('_mediaSurfaceTapTimer')));
      report.pass('M16.3');
    });
  });
}
