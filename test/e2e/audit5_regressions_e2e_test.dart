import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dacx/playback/audio_filter_chain.dart';
import 'package:dacx/playback/pictures_dir.dart';
import 'package:dacx/playback/player_path_utils.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/open_file_bridge.dart';

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
    String? initialFile,
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

  testWidgets('cold launch keeps the CLI file first with pending files', (
    tester,
  ) async {
    final one = p.normalize(p.absolute('media/one.mp3'));
    _pending(['/media/two.mp3', '/media/three.mp3']);
    final player = await pumpScreen(tester, initialFile: one);
    expect(player.openCalls.map((c) => c.path), [one]);
    expect(await _queueNames(tester, ['one.mp3', 'two.mp3', 'three.mp3']), [
      'one.mp3',
      'two.mp3',
      'three.mp3',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cold launch with only a CLI file opens it alone', (
    tester,
  ) async {
    final solo = p.normalize(p.absolute('media/solo.mp3'));
    final player = await pumpScreen(tester, initialFile: solo);
    expect(player.openCalls.map((c) => c.path), [solo]);
    expect(player.openCalls.single.play, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'bridge delivers the initial file when the native side is missing',
    () async {
      final opened = <String>[];
      final bridge = OpenFileBridge(
        onOpenRequest: (request, {required forcePlay}) async {
          opened.add(request.path);
        },
        onOpenBatch: (requests) async =>
            opened.addAll(requests.map((r) => r.path)),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlayerScreenHarness.openFileMethodsChannel,
            null,
          );
      await bridge.bootstrap(
        initial: const [OpenFileRequest(path: '/media/cli.mp3')],
      );
      bridge.dispose();
      expect(opened, ['/media/cli.mp3']);
    },
  );

  test(
    'failed af write never leaves a stale chain that skips the next',
    () async {
      final writes = <String>[];
      var fail = true;
      Future<bool> setter(String chain) async {
        writes.add(chain);
        return !fail;
      }

      final enabled = await AudioFilterChain.apply(
        lastAppliedChain: '',
        eqEnabled: true,
        eqBands: const [6, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        setAudioFilter: setter,
      );
      expect(enabled.failed, isTrue);
      fail = false;
      final disabled = await AudioFilterChain.apply(
        lastAppliedChain: enabled.appliedChain,
        eqEnabled: false,
        eqBands: const [6, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        setAudioFilter: setter,
      );
      expect(disabled.skipped, isFalse);
      expect(writes.last, '');
    },
  );

  group('pictures folder', () {
    test('Windows uses the known folder', () {
      expect(
        PicturesDir.resolve(
          os: 'windows',
          environment: const {'USERPROFILE': r'C:\Users\u'},
          windowsKnownFolder: () => r'D:\OneDrive\Pictures',
          readUserDirs: () => null,
          directoryExists: (_) => true,
        ),
        r'D:\OneDrive\Pictures',
      );
    });

    test('Windows falls back to the profile folder', () {
      expect(
        PicturesDir.resolve(
          os: 'windows',
          environment: const {'USERPROFILE': r'C:\Users\u'},
          windowsKnownFolder: () => null,
          readUserDirs: () => null,
          directoryExists: (_) => true,
        ),
        p.windows.join(r'C:\Users\u', 'Pictures'),
      );
    });

    test('native Linux uses the XDG pictures folder', () {
      expect(
        PicturesDir.resolve(
          os: 'linux',
          environment: const {'HOME': '/home/u'},
          windowsKnownFolder: () => null,
          readUserDirs: () => 'XDG_PICTURES_DIR="\$HOME/Bilder"\n',
          directoryExists: (path) => path == '/home/u/Bilder',
        ),
        '/home/u/Bilder',
      );
    });

    test('macOS keeps HOME/Pictures', () {
      expect(
        PicturesDir.resolve(
          os: 'macos',
          environment: const {'HOME': '/Users/u'},
          windowsKnownFolder: () => null,
          readUserDirs: () => null,
          directoryExists: (_) => true,
        ),
        p.posix.join('/Users/u', 'Pictures'),
      );
    });

    test('Windows known folder lookup matches the shell on this host', () {
      if (!Platform.isWindows) return;
      final known = PicturesDir.windowsKnownPicturesFolder();
      expect(known, isNotNull);
      expect(Directory(known!).existsSync(), isTrue);
    });
  });
}
