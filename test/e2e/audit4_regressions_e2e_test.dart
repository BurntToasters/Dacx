import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/open_file_bridge.dart';
import 'package:dacx/services/playlist_service.dart';

import '../support/player_screen_harness.dart';

Future<List<String>> _queueNames(
  WidgetTester tester,
  List<String> names,
) async {
  await tester.tap(find.byTooltip('Play Queue'));
  await tester.pumpAndSettle();
  return [
    for (final name in names)
      if (find.text(name).evaluate().isNotEmpty) name,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  testWidgets('pending Open With paths queue together and play the first', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlayerScreenHarness.openFileMethodsChannel, (
          call,
        ) async {
          if (call.method == 'getPendingFiles') {
            return <dynamic>[
              '/media/one.mp3',
              '/media/two.mp3',
              '/media/three.mp3',
            ];
          }
          return null;
        });
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
    expect(player.openCalls.map((c) => c.path), ['/media/one.mp3']);
    expect(await _queueNames(tester, ['one.mp3', 'two.mp3', 'three.mp3']), [
      'one.mp3',
      'two.mp3',
      'three.mp3',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    services.settings.dispose();
  });

  testWidgets('live Open With events in one burst queue together', (
    tester,
  ) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(OpenFileBridge.eventChannelName),
          MockStreamHandler.inline(
            onListen: (_, events) {
              sink = events;
            },
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(OpenFileBridge.eventChannelName),
            null,
          ),
    );
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
    expect(sink, isNotNull);
    sink!.success('/media/a.mp3');
    await tester.pump(const Duration(milliseconds: 50));
    sink!.success('/media/b.mp3');
    await tester.pump(const Duration(milliseconds: 50));
    sink!.success('/media/c.mp3');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(player.openCalls.map((c) => c.path), ['/media/a.mp3']);
    expect(await _queueNames(tester, ['a.mp3', 'b.mp3', 'c.mp3']), [
      'a.mp3',
      'b.mp3',
      'c.mp3',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    services.settings.dispose();
  });

  test('remove missing reports whether the current item was removed', () async {
    final dir = await Directory.systemTemp.createTemp('dacx-missing-');
    addTearDown(() => dir.delete(recursive: true));
    final kept = File(p.join(dir.path, 'kept.mp3'))..writeAsStringSync('x');
    final other = File(p.join(dir.path, 'other.mp3'))..writeAsStringSync('x');
    final gone = p.join(dir.path, 'gone.mp3');

    final survived = PlaylistService()..replace([kept.path, gone, other.path]);
    var currentRemoved = false;
    expect(
      await survived.removeMissingFiles(
        onCurrentRemoved: () => currentRemoved = true,
      ),
      1,
    );
    expect(currentRemoved, isFalse);
    expect(survived.current, PlayableSource.file(kept.path));

    final dropped = PlaylistService()
      ..replace([kept.path, gone, other.path], startIndex: 1);
    currentRemoved = false;
    await dropped.removeMissingFiles(
      onCurrentRemoved: () => currentRemoved = true,
    );
    expect(currentRemoved, isTrue);
  });

  test('Linux MPRIS name falls back to a per-instance name', () {
    expect(
      MediaSessionService.mprisPlayerName(baseNameTaken: false, pid: 42),
      'dacx',
    );
    expect(
      MediaSessionService.mprisPlayerName(baseNameTaken: true, pid: 42),
      'dacx.instance42',
    );
  });

  group('shuffle keeps history', () {
    List<String> names(int n) => [for (var i = 0; i < n; i++) '/m/$i.mp3'];

    PlaylistService shuffled(int n, {int steps = 2}) {
      final s = PlaylistService()..replace(names(n));
      s.setShuffle(true);
      for (var i = 0; i < steps; i++) {
        s.advance(1);
      }
      return s;
    }

    test('adding items keeps Previous and never inserts behind', () {
      for (var run = 0; run < 50; run++) {
        final s = shuffled(6);
        final snap = s.capture();
        final previous = s.items[snap.shuffleOrder[snap.shufflePos - 1]];
        final current = s.current;
        s.addAll(['/m/new-a.mp3', '/m/new-b.mp3']);
        final after = s.capture();
        expect(s.current, current);
        final played = after.shuffleOrder
            .take(after.shufflePos + 1)
            .map((i) => s.items[i].value);
        expect(played, isNot(contains('/m/new-a.mp3')));
        expect(played, isNot(contains('/m/new-b.mp3')));
        expect(s.advance(-1), previous);
      }
    });

    test('playing through after adds never repeats a track', () {
      for (var run = 0; run < 50; run++) {
        final s = shuffled(6);
        s.addAll(['/m/new-a.mp3']);
        final seen = <PlayableSource>{};
        final snap = s.capture();
        for (var k = 0; k <= snap.shufflePos; k++) {
          seen.add(s.items[snap.shuffleOrder[k]]);
        }
        while (s.hasNext) {
          expect(seen.add(s.advance(1)!), isTrue);
        }
        expect(seen.length, 7);
      }
    });

    test('removing current continues with the next shuffle item', () {
      for (var run = 0; run < 50; run++) {
        final s = shuffled(6);
        final snap = s.capture();
        final expected = s.items[snap.shuffleOrder[snap.shufflePos + 1]];
        s.removeAt(s.index);
        expect(s.current, expected);
      }
    });

    test('play next while shuffled plays the inserted item next', () {
      for (var run = 0; run < 50; run++) {
        final s = shuffled(6);
        s.playNext('/m/next.mp3');
        expect(s.advance(1), PlayableSource.file('/m/next.mp3'));
      }
    });

    test('reorder keeps current and Previous', () {
      for (var run = 0; run < 50; run++) {
        final s = shuffled(6);
        final snap = s.capture();
        final previous = s.items[snap.shuffleOrder[snap.shufflePos - 1]];
        final current = s.current;
        s.moveItem(0, 5);
        expect(s.current, current);
        expect(s.advance(-1), previous);
      }
    });

    test('turning shuffle on starts with the current item', () {
      final s = PlaylistService()..replace(names(6), startIndex: 3);
      s.setShuffle(true);
      final snap = s.capture();
      expect(snap.shufflePos, 0);
      expect(snap.shuffleOrder.first, 3);
    });
  });
}
