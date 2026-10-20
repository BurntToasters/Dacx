import 'package:dacx/services/headless_player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/player_screen_harness.dart';

void _pending(List<String> paths) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(PlayerScreenHarness.openFileMethodsChannel, (
        call,
      ) async {
        if (call.method == 'getPendingFiles') return <dynamic>[...paths];
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  Future<HeadlessPlayerService> pumpScreen(
    WidgetTester tester, {
    required String? initialFile,
  }) async {
    PlayerScreenHarness.configureDesktopViewport(tester);
    final services = await PlayerScreenHarness.createServices();
    addTearDown(services.settings.dispose);
    final player = HeadlessPlayerService();
    await tester.pumpWidget(
      PlayerScreenHarness.wrap(
        settings: services.settings,
        debugLog: services.debugLog,
        updates: services.updates,
        playerService: player,
        headlessMediaSurface: true,
        initialFile: initialFile,
      ),
    );
    await tester.pumpAndSettle();
    return player;
  }

  testWidgets('relative CLI path reaches the player as absolute', (
    tester,
  ) async {
    final player = await pumpScreen(tester, initialFile: 'media/song.mp3');
    expect(player.openCalls.map((c) => c.path), [
      p.normalize(p.absolute('media/song.mp3')),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dot and dot-dot segments are normalized', (tester) async {
    final player = await pumpScreen(
      tester,
      initialFile: './media/../media/./song.mp3',
    );
    expect(player.openCalls.map((c) => c.path), [
      p.normalize(p.absolute('media/song.mp3')),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('absolute CLI path is unchanged', (tester) async {
    final absolute = p.normalize(p.absolute('media/abs.mp3'));
    final player = await pumpScreen(tester, initialFile: absolute);
    expect(player.openCalls.map((c) => c.path), [absolute]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('http(s) URL CLI argument is unchanged', (tester) async {
    final player = await pumpScreen(
      tester,
      initialFile: 'https://example.com/a/./stream.mp3',
    );
    expect(player.openCalls.map((c) => c.path), [
      'https://example.com/a/./stream.mp3',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('file: URI CLI argument is not mangled', (tester) async {
    const uri = 'file:///media/uri%20song.mp3';
    final player = await pumpScreen(tester, initialFile: uri);
    expect(player.openCalls.map((c) => c.path), [uri]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty CLI input produces no open request', (tester) async {
    final player = await pumpScreen(tester, initialFile: '   ');
    expect(player.openCalls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending bridge paths are not rewritten', (tester) async {
    _pending(['relative/pending.mp3']);
    final player = await pumpScreen(tester, initialFile: null);
    expect(player.openCalls.map((c) => c.path), ['relative/pending.mp3']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cold launch keeps relative CLI file first with pending files', (
    tester,
  ) async {
    _pending(['relative/two.mp3']);
    final player = await pumpScreen(tester, initialFile: 'one.mp3');
    expect(player.openCalls.map((c) => c.path), [
      p.normalize(p.absolute('one.mp3')),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
