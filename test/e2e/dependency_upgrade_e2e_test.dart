import 'dart:io';

import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/open_file_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dacx/services/tray_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/player_screen_harness.dart';

/// Drop paths reach `_applyDroppedPaths` through `DropTarget.onDragDone`
/// (desktop_drop) and through `initialDropPaths`, which calls the same
/// method. These tests use `initialDropPaths` so they run headless.
Future<void> _settleRealIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tray service without native tray handles', () {
    setUp(PlayerScreenHarness.installChannelMocks);
    tearDown(PlayerScreenHarness.uninstallChannelMocks);

    test('init never throws and leaves the tray uninitialized', () async {
      var quitCalls = 0;
      final tray = TrayService(onQuit: () async => quitCalls++);
      await tray.init(showLabel: 'Show Dacx', quitLabel: 'Quit');
      expect(tray.isInitialized, isFalse);
      expect(quitCalls, 0);
    });

    test(
      'a second init after a failed init is safe and stays uninitialized',
      () async {
        final tray = TrayService(onQuit: () async {});
        await tray.init(showLabel: 'Show Dacx', quitLabel: 'Quit');
        await tray.init(showLabel: 'Afficher Dacx', quitLabel: 'Quitter');
        expect(tray.isInitialized, isFalse);
      },
    );

    test('dispose before init and repeated dispose are safe', () async {
      final tray = TrayService(onQuit: () async {});
      await tray.dispose();
      await tray.dispose();
      expect(tray.isInitialized, isFalse);
    });

    test('dispose after a failed init is safe and idempotent', () async {
      final tray = TrayService(onQuit: () async {});
      await tray.init(showLabel: 'Show Dacx', quitLabel: 'Quit');
      await tray.dispose();
      await tray.dispose();
      expect(tray.isInitialized, isFalse);
    });

    test(
      'hide to tray minimizes and never hides when no tray exists',
      () async {
        final tray = TrayService(onQuit: () async {});
        final hidden = await tray.hideToTray();
        expect(hidden, isFalse);
        final methods = PlayerScreenHarness.windowManagerCalls.map(
          (c) => c.method,
        );
        expect(methods, contains('minimize'));
        expect(methods, isNot(contains('hide')));
      },
    );
  });

  group('drop paths reach the player', () {
    late Directory tempDir;

    setUp(() {
      PlayerScreenHarness.installChannelMocks();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        const EventChannel(OpenFileBridge.eventChannelName),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => <String, dynamic>{
          'appName': 'Dacx',
          'packageName': 'run.rosie.dacx',
          'version': '1.0.0',
          'buildNumber': '1',
          'buildSignature': '',
        },
      );
      tempDir = Directory.systemTemp.createTempSync('dacx_dep_upgrade_drop_');
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        const EventChannel(OpenFileBridge.eventChannelName),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        null,
      );
      PlayerScreenHarness.uninstallChannelMocks();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<HeadlessPlayerService> pumpDrop(
      WidgetTester tester,
      List<String> paths,
    ) async {
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
          initialDropPaths: paths,
        ),
      );
      await tester.pump();
      await _settleRealIo(tester);
      return player;
    }

    testWidgets('a dropped media file is opened', (tester) async {
      final file = File(p.join(tempDir.path, 'single.mp3'))
        ..writeAsBytesSync(const [0]);
      final player = await pumpDrop(tester, [file.path]);
      expect(player.openCalls.map((c) => c.path), [file.path]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a dropped folder expands to its media and skips other files', (
      tester,
    ) async {
      final folder = Directory(p.join(tempDir.path, 'album'))..createSync();
      final song = File(p.join(folder.path, 'song.mp3'))
        ..writeAsBytesSync(const [0]);
      final notes = File(p.join(folder.path, 'notes.txt'))
        ..writeAsStringSync('not media');
      final player = await pumpDrop(tester, [folder.path]);
      final opened = player.openCalls.map((c) => c.path).toList();
      expect(opened, contains(song.path));
      expect(opened, isNot(contains(folder.path)));
      expect(opened, isNot(contains(notes.path)));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a dropped m3u playlist queues its entries', (tester) async {
      final playlist = File(p.join(tempDir.path, 'set.m3u'))
        ..writeAsStringSync('/media/dep_one.mp3\n/media/dep_two.flac\n');
      final player = await pumpDrop(tester, [playlist.path]);
      final opened = player.openCalls.map((c) => c.path).toList();
      expect(opened, contains('/media/dep_one.mp3'));
      expect(opened, isNot(contains(playlist.path)));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a dropped http(s) URL is treated as a non-local source', (
      tester,
    ) async {
      const url = 'https://example.com/stream/dep.mp3';
      final player = await pumpDrop(tester, [url]);
      expect(player.openCalls.map((c) => c.path), [url]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('empty and blank drops open nothing', (tester) async {
      final player = await pumpDrop(tester, ['', '   ']);
      expect(player.openCalls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
