import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/drop_path_batch_policy.dart';
import 'package:dacx/playback/m3u_playlist.dart';
import 'package:dacx/playback/player_path_utils.dart';
import 'package:dacx/playback/source_load_validation_policy.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/open_file_bridge.dart';
import 'package:dacx/services/windows_shell_service.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _invalidPathMessage = 'Invalid file path. Try another file.';
const _skippedOneMessage = 'Skipped 1 unreadable file.';
const _playlistImportFailedMessage = 'Could not import playlist';
const _folderScanFailedPrefix = 'Could not scan folder.';
const _nextTrackTooltip = 'Next Track (Shift+N)';

const _uncFile = r'\\localhost\dacx_unc_test\music\song.mp3';
const _uncFileB = r'\\localhost\dacx_unc_test\music\other.flac';
const _uncFolder = r'\\localhost\dacx_unc_test\music';
const _uncPlaylist = r'\\localhost\dacx_unc_test\lists\mix.m3u';
const _uncAudio = r'\\localhost\dacx_unc_test\extra\dub.flac';
const _uncSubtitle = r'\\localhost\dacx_unc_test\extra\movie.srt';

final class _FolderPicker extends FilePickerPlatform {
  _FolderPicker(this.folder);

  final String folder;
  int calls = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    return folder;
  }
}

Future<HeadlessPlayerService> pumpPlayer(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  HeadlessPlayerService? player,
  PlayableSource? loaded,
  List<PlayableSource>? playlist,
  List<String>? drops,
  PlayableSource? pending,
  String? initialFile,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
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
      initialLoadedSource: loaded,
      initialPlaylistSources: playlist,
      initialDropPaths: drops,
      initialPendingLoad: pending,
      initialFile: initialFile,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return service;
}

Future<void> settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> realIoDelay(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
}

Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
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

Future<void> openMoreMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Directory makeTempDir() {
  final dir = Directory.systemTemp.createTempSync('dacx_a9_unc_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

List<String> openedPaths(HeadlessPlayerService player) =>
    player.openCalls.map((c) => c.path).toList(growable: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'unc',
    expectedIds: [for (var i = 1; i <= 19; i++) 'M37.$i'],
  );
  tearDownAll(report.write);

  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );

  setUp(() {
    PlayerScreenHarness.installChannelMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(OpenFileBridge.eventChannelName),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          packageInfoChannel,
          (call) async => <String, dynamic>{
            'appName': 'Dacx',
            'packageName': 'run.rosie.dacx',
            'version': '1.0.0',
            'buildNumber': '1',
            'buildSignature': '',
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(OpenFileBridge.eventChannelName),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    PlayerScreenHarness.uninstallChannelMocks();
  });

  group('Finding 37: path rules', () {
    const uncForms = [
      r'\\server\share\a.mp3',
      '//server/share/a.mp3',
      r'\\?\UNC\server\share\a.mp3',
    ];

    test('M37.1 default isUnsafeOpenPath refuses every UNC form', () {
      for (final path in uncForms) {
        expect(PlayerPathUtils.isUnsafeOpenPath(path), isTrue, reason: path);
        expect(
          PlayerPathUtils.isUnsafeOpenPath(path, allowUnc: false),
          isTrue,
          reason: path,
        );
      }
      report.pass('M37.1');
    });

    test('M37.2 allowUnc accepts every UNC form', () {
      for (final path in uncForms) {
        expect(
          PlayerPathUtils.isUnsafeOpenPath(path, allowUnc: true),
          isFalse,
          reason: path,
        );
        expect(PlayerPathUtils.isUncPath(path), isTrue, reason: path);
      }
      report.pass('M37.2');
    });

    test('M37.3 allowUnc keeps every other unsafe rule', () {
      const stillUnsafe = [
        '',
        '   ',
        'a\x00b.mp3',
        '\\\\server\\share\\a\x00.mp3',
        'lavfi://sine',
        'ytdl://abc',
        'edl://file.mp3',
        'https://user:pw@example.com/a.mp3',
        r'\\.\pipe\name',
        r'\\?\C:\media\a.mp3',
        r'\\?\GLOBALROOT\Device\x',
        '//?/C:/media/a.mp3',
      ];
      for (final path in stillUnsafe) {
        expect(
          PlayerPathUtils.isUnsafeOpenPath(path, allowUnc: true),
          isTrue,
          reason: path,
        );
      }
      expect(
        PlayerPathUtils.isUnsafeOpenPath(r'C:\media\a.mp3', allowUnc: true),
        isFalse,
      );
      report.pass('M37.3');
    });

    test('M37.4 origins decide whether UNC is allowed', () {
      const allowed = {
        SourceOrigin.fileDialog,
        SourceOrigin.folderDialog,
        SourceOrigin.dragDrop,
        SourceOrigin.recents,
        SourceOrigin.queue,
      };
      const blocked = {
        SourceOrigin.commandLine,
        SourceOrigin.forwarded,
        SourceOrigin.playlistEntry,
        SourceOrigin.mediaSession,
        SourceOrigin.other,
      };
      expect({...allowed, ...blocked}, SourceOrigin.values.toSet());
      for (final origin in allowed) {
        expect(origin.allowsUnc, isTrue, reason: origin.name);
      }
      for (final origin in blocked) {
        expect(origin.allowsUnc, isFalse, reason: origin.name);
      }
      report.pass('M37.4');
    });

    test('M37.5 load validation follows the origin', () {
      final source = PlayableSource.file(r'\\server\share\a.mp3');
      SourceLoadValidationFailure failureFor([SourceOrigin? origin]) {
        return origin == null
            ? SourceLoadValidationPolicy.validateRequest(
                source: source,
                trimmedValue: source.value,
              ).failure
            : SourceLoadValidationPolicy.validateRequest(
                source: source,
                trimmedValue: source.value,
                origin: origin,
              ).failure;
      }

      expect(failureFor(), SourceLoadValidationFailure.unsafePath);
      for (final origin in SourceOrigin.values) {
        expect(
          failureFor(origin),
          origin.allowsUnc
              ? SourceLoadValidationFailure.none
              : SourceLoadValidationFailure.unsafePath,
          reason: origin.name,
        );
      }
      final normalized = SourceLoadValidationPolicy.validateNormalizedOpen(
        source: source,
        trimmedValue: source.value,
        normalizedSource: source,
        fileExists: true,
        origin: SourceOrigin.fileDialog,
      );
      expect(normalized.isOk, isTrue);
      final refused = SourceLoadValidationPolicy.validateNormalizedOpen(
        source: source,
        trimmedValue: source.value,
        normalizedSource: source,
        fileExists: true,
      );
      expect(refused.failure, SourceLoadValidationFailure.unsafePath);
      expect(
        SourceLoadValidationPolicy.validateRequest(
          source: PlayableSource.file('a\x00b.mp3'),
          trimmedValue: 'a\x00b.mp3',
          origin: SourceOrigin.fileDialog,
        ).failure,
        SourceLoadValidationFailure.unsafePath,
      );
      report.pass('M37.5');
    });
  });

  group('Finding 37: dialogs', () {
    testWidgets('M37.6 open-file dialog loads a UNC path', (tester) async {
      PlayerScreenHarness.filePickerPaths = [_uncFile];
      final player = await pumpPlayer(tester);
      await pressCtrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);

      expect(openedPaths(player), [_uncFile]);
      expect(find.text(_invalidPathMessage), findsNothing);
      report.pass('M37.6');
    });

    testWidgets('M37.7 add-files dialog queues and opens UNC paths', (
      tester,
    ) async {
      PlayerScreenHarness.filePickerPaths = [_uncFile, _uncFileB];
      final player = await pumpPlayer(tester);
      await openQueueDrawer(tester);
      await tapAddFiles(tester);
      await settle(tester);

      expect(openedPaths(player), [_uncFile]);
      expect(find.text(_invalidPathMessage), findsNothing);
      expect(find.text('song.mp3'), findsWidgets);
      expect(find.text('other.flac'), findsWidgets);
      report.pass('M37.7');
    });

    testWidgets('M37.8 external audio and subtitle pickers accept UNC', (
      tester,
    ) async {
      final player = await pumpPlayer(
        tester,
        loaded: PlayableSource.file('/media/movie.mkv'),
      );
      PlayerScreenHarness.filePickerPaths = [_uncAudio];
      await openMoreMenuItem(tester, 'Load external audio…');
      PlayerScreenHarness.filePickerPaths = [_uncSubtitle];
      await openMoreMenuItem(tester, 'Load external subtitle…');

      expect(player.commandCalls, [
        ['audio-add', _uncAudio, 'select'],
        ['sub-add', _uncSubtitle, 'select'],
      ]);
      expect(find.text('Could not load external audio'), findsNothing);
      expect(find.text('Could not load external subtitle'), findsNothing);
      final bare = HeadlessPlayerService();
      expect(await bare.addExternalAudio(_uncAudio), isFalse);
      expect(await bare.addExternalSubtitle(_uncSubtitle), isFalse);
      expect(bare.commandCalls, isEmpty);
      expect(await bare.addExternalAudio(_uncAudio, allowUnc: true), isTrue);
      expect(
        await bare.addExternalSubtitle(_uncSubtitle, allowUnc: true),
        isTrue,
      );
      report.pass('M37.8');
    });

    testWidgets('M37.9 folder dialog accepts a UNC folder', (tester) async {
      final picker = _FolderPicker(_uncFolder);
      final player = await pumpPlayer(tester);
      FilePickerPlatform.instance = picker;
      await tester.tap(find.byKey(const Key('open-folder-transport-button')));
      await tester.pump();
      final scanFailed = find.textContaining(_folderScanFailedPrefix);
      for (var i = 0; i < 6 && scanFailed.evaluate().isEmpty; i++) {
        await realIoDelay(tester);
      }

      expect(picker.calls, 1);
      expect(find.text(_invalidPathMessage), findsNothing);
      expect(scanFailed, findsOneWidget);
      expect(player.openCalls, isEmpty);
      expect(SourceOrigin.folderDialog.allowsUnc, isTrue);
      report.pass('M37.9');
    });

    testWidgets('M37.17 a non-UNC unsafe dialog path is still refused', (
      tester,
    ) async {
      PlayerScreenHarness.filePickerPaths = ['lavfi://sine'];
      final player = await pumpPlayer(tester);
      await pressCtrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);

      expect(player.openCalls, isEmpty);
      expect(find.text(_invalidPathMessage), findsOneWidget);
      report.pass('M37.17');
    });
  });

  group('Finding 37: drops, recents and queue', () {
    testWidgets('M37.10 drops keep UNC and local paths', (tester) async {
      const raw = [r'\\server\share\a.mp3', r'C:\media\b.mp3'];
      final refused = DropPathBatchPolicy.fromRawPaths(
        rawPaths: raw,
        windows: true,
      );
      expect(refused.paths, [r'C:\media\b.mp3']);
      expect(refused.skippedCount, 1);
      final allowed = DropPathBatchPolicy.fromRawPaths(
        rawPaths: [...raw, 'lavfi://sine'],
        windows: true,
        allowUnc: true,
      );
      expect(allowed.paths, raw);
      expect(allowed.skippedCount, 1);

      final single = await pumpPlayer(tester, drops: [_uncFile]);
      await settle(tester);
      expect(openedPaths(single), [_uncFile]);
      expect(find.text(_skippedOneMessage), findsNothing);
      expect(find.text('Could not read dropped file path.'), findsNothing);

      final mixed = await pumpPlayer(
        tester,
        drops: [_uncFile, '/media/local.mp3', _uncFileB],
      );
      await settle(tester);
      expect(openedPaths(mixed), [_uncFile]);
      await openQueueDrawer(tester);
      expect(find.text('song.mp3'), findsWidgets);
      expect(find.text('local.mp3'), findsWidgets);
      expect(find.text('other.flac'), findsWidgets);
      expect(find.text(_skippedOneMessage), findsNothing);
      report.pass('M37.10');
    });

    testWidgets('M37.11 a UNC recents entry reopens', (tester) async {
      final player = await pumpPlayer(
        tester,
        prefs: {
          'recent_files': jsonEncode([_uncFile]),
        },
      );
      await tester.tap(find.byTooltip('Recent files'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>(_uncFile)));
      await tester.pump();
      await settle(tester);

      expect(openedPaths(player), [_uncFile]);
      expect(find.text(_invalidPathMessage), findsNothing);
      report.pass('M37.11');
    });

    testWidgets('M37.12 advancing to a UNC queue entry opens it', (
      tester,
    ) async {
      final player = await pumpPlayer(
        tester,
        pending: PlayableSource.file('/media/first.mp3'),
        playlist: [
          PlayableSource.file('/media/first.mp3'),
          PlayableSource.file(_uncFile),
        ],
      );
      await settle(tester);
      expect(openedPaths(player), ['/media/first.mp3']);
      await tester.tap(find.byTooltip(_nextTrackTooltip));
      await tester.pump();
      await settle(tester);

      expect(openedPaths(player), ['/media/first.mp3', _uncFile]);
      expect(find.text(_invalidPathMessage), findsNothing);
      report.pass('M37.12');
    });
  });

  group('Finding 37: untrusted origins stay refused', () {
    testWidgets('M37.13 a UNC command-line file is refused with the message', (
      tester,
    ) async {
      final player = await pumpPlayer(tester, initialFile: _uncFile);
      await settle(tester);

      expect(player.openCalls, isEmpty);
      expect(find.text(_invalidPathMessage), findsOneWidget);
      report.pass('M37.13');
    });

    testWidgets('M37.14 forwarded UNC paths are never opened', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlayerScreenHarness.openFileMethodsChannel,
            (call) async {
              if (call.method == 'getPendingFiles') {
                return <dynamic>[_uncFileB, '/media/pending.mp3'];
              }
              return null;
            },
          );
      final alone = await pumpPlayer(tester);
      await tester.pumpAndSettle();
      expect(openedPaths(alone), ['/media/pending.mp3']);
      expect(find.text(_invalidPathMessage), findsNothing);

      final batch = await pumpPlayer(tester, initialFile: _uncFile);
      await tester.pumpAndSettle();
      expect(openedPaths(batch), ['/media/pending.mp3']);
      expect(find.text(_skippedOneMessage), findsOneWidget);
      report.pass('M37.14');
    });

    testWidgets('M37.15 UNC entries in a picked playlist stay refused', (
      tester,
    ) async {
      final dir = makeTempDir();
      final playlist = File('${dir.path}${Platform.pathSeparator}mix.m3u');
      playlist.writeAsStringSync('$_uncFile\n/media/local.mp3\n$_uncFileB\n');
      PlayerScreenHarness.filePickerPaths = [playlist.path];
      final player = await pumpPlayer(tester);
      await pressCtrl(tester, LogicalKeyboardKey.keyO);
      await realIoDelay(tester);
      await settle(tester);

      expect(openedPaths(player), ['/media/local.mp3']);
      expect(
        M3uPlaylist.parse(
          '$_uncFile\nrelative.mp3\n/media/local.mp3\n',
          baseDir: r'\\server\share\music',
        ).map((s) => s.value),
        ['/media/local.mp3'],
      );
      expect(
        M3uPlaylist.parse(
          '[playlist]\nFile1=$_uncFile\nFile2=/media/local.mp3\n',
        ).map((s) => s.value),
        ['/media/local.mp3'],
      );
      report.pass('M37.15');
    });

    testWidgets('M37.16 a UNC playlist file is read, not refused', (
      tester,
    ) async {
      PlayerScreenHarness.filePickerPaths = [_uncPlaylist];
      final player = await pumpPlayer(tester);
      await pressCtrl(tester, LogicalKeyboardKey.keyO);
      await realIoDelay(tester);
      await settle(tester);

      expect(player.openCalls, isEmpty);
      expect(find.text(_invalidPathMessage), findsNothing);
      expect(find.text(_playlistImportFailedMessage), findsOneWidget);
      report.pass('M37.16');
    });
  });

  group('Finding 37: service and shell', () {
    test('M37.18 the player service needs the explicit flag for UNC', () async {
      final player = HeadlessPlayerService();
      await expectLater(player.open(_uncFile), throwsA(isA<ArgumentError>()));
      expect(player.openCalls, isEmpty);
      await expectLater(
        player.open(r'\\?\C:\media\a.mp3', allowUnc: true),
        throwsA(isA<ArgumentError>()),
      );
      await player.open(_uncFile, allowUnc: true);
      await player.open('/media/local.mp3');
      expect(openedPaths(player), [_uncFile, '/media/local.mp3']);
      report.pass('M37.18');
    });

    test('M37.19 the jump list still drops UNC paths', () {
      expect(
        WindowsShellService.filterJumpListPaths([_uncFile, r'C:\media\a.mp3']),
        [r'C:\media\a.mp3'],
      );
      report.pass('M37.19');
    });
  });
}
