import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/l10n/app_localizations_en.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/widgets/player_bottom_dock.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

final _l10n = AppLocalizationsEn();

const _titleOverlay = ValueKey('fullscreen-title-overlay');
const _dockOverlay = ValueKey('fullscreen-dock-overlay');
const _overlayOpacity = ValueKey('chrome-overlay-opacity');
const _caption = Key('audio-caption');
const _uncFile = r'\\localhost\dacx_wiring_test\music\song.mp3';
const _hideDelay = Duration(seconds: 3);
const _recheckDelay = Duration(milliseconds: 250);

class _TaggedPlayer extends HeadlessPlayerService {
  final Map<String, Map<String, String>> tags = {};
  final Map<String, Completer<void>> titleGates = {};

  @override
  Future<String?> getProperty(String name) async {
    const prefix = 'metadata/by-key/';
    if (!name.startsWith(prefix)) return super.getProperty(name);
    final path = await super.getProperty('path');
    final fileName = path == null ? '' : p.basename(path);
    final key = name.substring(prefix.length);
    if (key == 'title') {
      final gate = titleGates[fileName];
      if (gate != null) await gate.future;
    }
    return tags[fileName]?[key];
  }
}

class _TimerLog {
  final List<({Duration duration, bool periodic})> entries = [];

  void clear() => entries.clear();

  int get hideTimers => entries
      .where((entry) => !entry.periodic && entry.duration == _hideDelay)
      .length;

  List<({Duration duration, bool periodic})> get rechecks => entries
      .where((entry) => entry.periodic || entry.duration == _recheckDelay)
      .toList();
}

Future<T> _inLoggedZone<T>(_TimerLog log, Future<T> Function() body) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        log.entries.add((duration: duration, periodic: false));
        return parent.createTimer(zone, duration, callback);
      },
      createPeriodicTimer: (self, parent, zone, period, callback) {
        log.entries.add((duration: period, periodic: true));
        return parent.createPeriodicTimer(zone, period, callback);
      },
    ),
  );
}

Future<({SettingsService settings, HeadlessPlayerService player})> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  HeadlessPlayerService? player,
  PlayableSource? pending,
  List<PlayableSource>? playlist,
  Size? size,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  if (size != null) tester.view.physicalSize = size;
  final services = await PlayerScreenHarness.createServices(prefs: prefs);
  final service = player ?? HeadlessPlayerService();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    PlayerScreenHarness.wrap(
      settings: services.settings,
      debugLog: services.debugLog,
      updates: services.updates,
      playerService: service,
      headlessMediaSurface: true,
      initialPlaylistSources: playlist,
      initialPendingLoad: pending,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (settings: services.settings, player: service);
}

Future<void> _settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

IconButton _iconButton(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
    );

bool _enabled(WidgetTester tester, IconData icon) =>
    _iconButton(tester, icon).onPressed != null;

List<String> _opened(HeadlessPlayerService player) => [
  for (final call in player.openCalls) call.path,
];

String? _captionText(WidgetTester tester) {
  final finder = find.byKey(_caption);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

Finder _menuItems() => find.byWidgetPredicate(
  (w) => w is MenuItemButton || w is SubmenuButton,
  description: 'top level menu items',
);

Rect _menuRect() {
  Rect? union;
  for (final element in _menuItems().evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    union = union == null ? rect : union.expandToInclude(rect);
  }
  return union!;
}

Future<void> _openQueue(WidgetTester tester) async {
  if (find.text('Play queue').evaluate().isNotEmpty) return;
  await tester.tap(find.byTooltip('Play Queue'));
  await tester.pumpAndSettle();
}

Future<void> _playQueueItem(WidgetTester tester, String name) async {
  await _openQueue(tester);
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(name)),
  );
  await tester.pump();
  await _settle(tester);
}

Future<void> _enterFullscreen(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(PlayerScreenHarness.fullscreenCalls.last, isTrue);
}

bool _shown(WidgetTester tester, ValueKey<String> overlay) {
  final opacity = find.descendant(
    of: find.byKey(overlay),
    matching: find.byKey(_overlayOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity).opacity > 0.5;
}

Future<void> _elapse(WidgetTester tester, Duration duration) =>
    tester.pump(duration);

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('dacx_wiring_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

List<String> _makeFiles(Directory dir, int count) => [
  for (var i = 0; i < count; i++)
    (File(p.join(dir.path, 'track$i.mp3'))..writeAsBytesSync([0])).path,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'wiring',
    expectedIds: [
      'M8.11',
      'M8.12',
      'M8.13',
      'M8.14',
      'M11.9',
      'M20.8',
      'M20.9',
      'M21.14',
      'M22.10',
      'M22.11',
    ],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 11: previous and next follow the queue', () {
    testWidgets('M11.9 the screen feeds its playlist to the dock', (
      tester,
    ) async {
      final a = PlayableSource.file('/media/a.mp3');
      final b = PlayableSource.file('/media/b.mp3');
      final single = await _pump(tester, pending: a, playlist: [a]);
      await _settle(tester);
      expect(find.byType(PlayerBottomDock), findsOneWidget);
      expect(_opened(single.player), ['/media/a.mp3']);

      expect(_enabled(tester, Icons.skip_next), isFalse);
      expect(_enabled(tester, Icons.skip_previous), isFalse);
      await tester.tap(find.byIcon(Icons.skip_next), warnIfMissed: false);
      await tester.pump();
      await _settle(tester);
      expect(_opened(single.player), ['/media/a.mp3']);

      single.settings.loopMode = LoopMode.loop;
      await tester.pump();
      expect(_enabled(tester, Icons.skip_next), isTrue);
      expect(_enabled(tester, Icons.skip_previous), isTrue);

      single.settings.loopMode = LoopMode.single;
      await tester.pump();
      expect(_enabled(tester, Icons.skip_next), isFalse);
      expect(_enabled(tester, Icons.skip_previous), isFalse);

      final pair = await _pump(tester, pending: a, playlist: [a, b]);
      await _settle(tester);
      expect(_enabled(tester, Icons.skip_next), isTrue);
      expect(_enabled(tester, Icons.skip_previous), isFalse);
      await tester.tap(find.byIcon(Icons.skip_next));
      await tester.pump();
      await _settle(tester);
      expect(_opened(pair.player), ['/media/a.mp3', '/media/b.mp3']);
      expect(_enabled(tester, Icons.skip_next), isFalse);
      expect(_enabled(tester, Icons.skip_previous), isTrue);

      final compact = await _pump(
        tester,
        pending: a,
        playlist: [a],
        size: const Size(700, 700),
      );
      await _settle(tester);
      expect(_opened(compact.player), ['/media/a.mp3']);
      expect(_enabled(tester, Icons.skip_next), isFalse);
      expect(_enabled(tester, Icons.skip_previous), isFalse);
      compact.settings.loopMode = LoopMode.loop;
      await tester.pump();
      expect(_enabled(tester, Icons.skip_next), isTrue);
      expect(_enabled(tester, Icons.skip_previous), isTrue);
      report.pass('M11.9');
    });
  });

  group('Finding 21: more menu anchors to its button', () {
    Future<void> checkAnchored(WidgetTester tester, Size? size) async {
      await _pump(
        tester,
        pending: PlayableSource.file('/media/a.mp3'),
        size: size,
      );
      await _settle(tester);
      final button = tester.getRect(find.byTooltip('More'));
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final menu = _menuRect();
      expect(menu.right, closeTo(button.right, 4));
      expect(menu.bottom, lessThanOrEqualTo(button.top + 4));
      expect(menu.right, isNot(closeTo(viewport.width - 12, 8)));
      expect(menu.left, greaterThanOrEqualTo(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_menuItems(), findsNothing);
    }

    testWidgets('M21.14 menu opens next to the More button', (tester) async {
      await checkAnchored(tester, null);
      await checkAnchored(tester, const Size(700, 700));
      report.pass('M21.14');
    });
  });

  group('Finding 22: empty state recents', () {
    testWidgets('M22.10 recents and reopen last only when recents exist', (
      tester,
    ) async {
      final dir = _tempDir();
      final none = await _pump(tester);
      await _settle(tester);
      expect(find.byKey(const Key('open-file-empty-button')), findsOneWidget);
      expect(find.byKey(const Key('reopen-last-empty-button')), findsNothing);
      expect(find.byKey(const Key('empty-recent-0')), findsNothing);
      expect(none.settings.recentFiles, isEmpty);

      final files = _makeFiles(dir, 6);
      final some = await _pump(
        tester,
        prefs: {'recent_files': jsonEncode(files)},
      );
      await _settle(tester);
      expect(some.settings.recentFiles, files);
      expect(find.byKey(const Key('reopen-last-empty-button')), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('empty-recent-$i')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(Key('empty-recent-$i')),
            matching: find.text('track$i.mp3'),
          ),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('empty-recent-5')), findsNothing);

      some.settings.clearRecentFiles();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('reopen-last-empty-button')), findsNothing);
      expect(find.byKey(const Key('empty-recent-0')), findsNothing);
      report.pass('M22.10');
    });

    testWidgets('M22.11 a tapped recent opens through the recents origin', (
      tester,
    ) async {
      final unc = await _pump(
        tester,
        prefs: {
          'recent_files': jsonEncode([_uncFile]),
        },
      );
      await _settle(tester);
      expect(find.byKey(const Key('empty-recent-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-recent-0')));
      await tester.pump();
      await _settle(tester);
      expect(_opened(unc.player), [_uncFile]);
      expect(find.text(_l10n.snackInvalidFilePath), findsNothing);

      final dir = _tempDir();
      final files = _makeFiles(dir, 3);
      final reopen = await _pump(
        tester,
        prefs: {'recent_files': jsonEncode(files)},
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('reopen-last-empty-button')));
      await tester.pump();
      await _settle(tester);
      expect(_opened(reopen.player).map(p.basename), ['track0.mp3']);

      final pick = await _pump(
        tester,
        prefs: {'recent_files': jsonEncode(files)},
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('empty-recent-2')));
      await tester.pump();
      await _settle(tester);
      expect(_opened(pick.player).map(p.basename), ['track2.mp3']);
      expect(pick.settings.recentFiles.first, endsWith('track2.mp3'));
      report.pass('M22.11');
    });
  });

  group('Finding 20: album caption from tags', () {
    _TaggedPlayer taggedPlayer() {
      final player = _TaggedPlayer();
      player.tags['a.mp3'] = {
        'title': 'Song A',
        'artist': 'Artist A',
        'album': 'Album A',
      };
      player.tags['b.mp3'] = {'title': 'Song B', 'album': 'Album B'};
      player.tags['c.mp3'] = {'title': 'Song C'};
      return player;
    }

    final a = PlayableSource.file('/music/a.mp3');
    final b = PlayableSource.file('/music/b.mp3');
    final c = PlayableSource.file('/music/c.mp3');

    testWidgets('M20.8 the album replaces the static caption', (tester) async {
      for (final session in [false, true]) {
        final player = taggedPlayer();
        await _pump(
          tester,
          prefs: {'media_session_enabled': session},
          player: player,
          pending: a,
          playlist: [a, b, c],
        );
        await _settle(tester);
        expect(find.byKey(const Key('audio-title')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('audio-title'))).data,
          'Song A',
          reason: 'session=$session',
        );
        expect(_captionText(tester), 'Album A', reason: 'session=$session');

        await _playQueueItem(tester, 'c.mp3');
        await _settle(tester);
        expect(
          _captionText(tester),
          _l10n.labelAudioPlayback,
          reason: 'session=$session',
        );
      }
      report.pass('M20.8');
    });

    testWidgets('M20.9 the album never outlives its track', (tester) async {
      final player = taggedPlayer();
      final gateB = Completer<void>();
      player.titleGates['b.mp3'] = gateB;
      await _pump(
        tester,
        prefs: {'media_session_enabled': false},
        player: player,
        pending: a,
        playlist: [a, b, c],
      );
      await _settle(tester);
      expect(_captionText(tester), 'Album A');

      await _playQueueItem(tester, 'b.mp3');
      expect(find.byKey(const Key('audio-title')), findsOneWidget);
      expect(_captionText(tester), _l10n.labelAudioPlayback);
      expect(find.text('Album A'), findsNothing);

      await _playQueueItem(tester, 'a.mp3');
      expect(_captionText(tester), 'Album A');
      gateB.complete();
      await _settle(tester);
      expect(_captionText(tester), 'Album A');
      expect(find.text('Album B'), findsNothing);

      if (find.text('Play queue').evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      await _settle(tester);
      expect(find.byKey(_caption), findsNothing);

      final gateAgain = Completer<void>();
      player.titleGates['b.mp3'] = gateAgain;
      await _playQueueItem(tester, 'b.mp3');
      expect(find.byKey(_caption), findsOneWidget);
      expect(_captionText(tester), _l10n.labelAudioPlayback);
      expect(find.text('Album A'), findsNothing);
      gateAgain.complete();
      await _settle(tester);
      expect(_captionText(tester), 'Album B');
      report.pass('M20.9');
    });
  });

  group('Finding 8: controls hold is driven by events', () {
    testWidgets('M8.11 paused in fullscreen creates no recheck timers', (
      tester,
    ) async {
      final log = _TimerLog();
      await _inLoggedZone(log, () async {
        await _pump(tester);
        log.clear();
        await _enterFullscreen(tester);
        expect(log.hideTimers, greaterThanOrEqualTo(1));

        await _elapse(tester, const Duration(seconds: 10));
        expect(_shown(tester, _dockOverlay), isTrue);
        expect(_shown(tester, _titleOverlay), isTrue);
        expect(log.rechecks, isEmpty);
      });
      report.pass('M8.11');
    });

    testWidgets('M8.12 resuming playback starts the hide countdown', (
      tester,
    ) async {
      final log = _TimerLog();
      await _inLoggedZone(log, () async {
        final rig = await _pump(tester);
        rig.player.emitPlaying(true);
        await tester.pump();
        await _enterFullscreen(tester);
        await _elapse(tester, const Duration(seconds: 4));
        expect(_shown(tester, _dockOverlay), isFalse);

        rig.player.emitPlaying(false);
        await tester.pump();
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(seconds: 10));
        expect(_shown(tester, _dockOverlay), isTrue);

        log.clear();
        rig.player.emitPlaying(true);
        await tester.pump();
        expect(log.hideTimers, 1);
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(milliseconds: 2500));
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(milliseconds: 1000));
        expect(_shown(tester, _dockOverlay), isFalse);

        rig.player.emitPlaying(false);
        await tester.pump();
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(seconds: 10));
        expect(_shown(tester, _dockOverlay), isTrue);
        expect(log.rechecks, isEmpty);
      });
      report.pass('M8.12');
    });

    testWidgets('M8.13 the queue drawer holds and releases the controls', (
      tester,
    ) async {
      final log = _TimerLog();
      await _inLoggedZone(log, () async {
        final rig = await _pump(tester);
        rig.player.emitPlaying(true);
        await tester.pump();
        await _enterFullscreen(tester);

        await tester.tap(find.byTooltip('Play Queue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Play queue'), findsOneWidget);
        log.clear();
        await _elapse(tester, const Duration(seconds: 10));
        expect(_shown(tester, _dockOverlay), isTrue);
        expect(log.rechecks, isEmpty);

        log.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(log.hideTimers, 1);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Play queue'), findsNothing);
        await _elapse(tester, const Duration(milliseconds: 2000));
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(milliseconds: 1000));
        expect(_shown(tester, _dockOverlay), isFalse);
        expect(log.rechecks, isEmpty);
      });
      report.pass('M8.13');
    });

    testWidgets('M8.14 a dialog above the player holds the controls', (
      tester,
    ) async {
      final log = _TimerLog();
      await _inLoggedZone(log, () async {
        final rig = await _pump(tester);
        rig.player.emitPlaying(true);
        await tester.pump();
        await _enterFullscreen(tester);

        final context = tester.element(find.byType(PlayerBottomDock));
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('probe dialog')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('probe dialog'), findsOneWidget);
        log.clear();
        await _elapse(tester, const Duration(seconds: 10));
        expect(_shown(tester, _dockOverlay), isTrue);
        expect(log.rechecks, isEmpty);

        log.clear();
        Navigator.of(context).pop();
        await tester.pump();
        expect(log.hideTimers, 1);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('probe dialog'), findsNothing);
        await _elapse(tester, const Duration(milliseconds: 2000));
        expect(_shown(tester, _dockOverlay), isTrue);
        await _elapse(tester, const Duration(milliseconds: 1000));
        expect(_shown(tester, _dockOverlay), isFalse);
        expect(log.rechecks, isEmpty);
      });
      report.pass('M8.14');
    });
  });
}
