import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/drop_path_batch_policy.dart';
import 'package:dacx/playback/media_folder_scanner.dart';
import 'package:dacx/playback/playback_speed_policy.dart';
import 'package:dacx/playback/player_controller.dart';
import 'package:dacx/playback/player_path_utils.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/equalizer_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/widgets/advanced_playback_dialog.dart';
import 'package:dacx/widgets/equalizer_dialog.dart';
import 'package:dacx/widgets/media_info_dialog.dart';
import 'package:dacx/widgets/osd_overlay.dart';
import 'package:dacx/widgets/seek_slider.dart';
import 'package:dacx/widgets/transport_controls.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _newAudio = ['m4b', 'oga', 'mka', 'ac3', 'eac3', 'dts', 'amr', 'weba'];
const _newVideo = ['3gp', 'f4v'];

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void _setWindow(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder get _dialogContentBox => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byWidgetPredicate(
    (w) => w is SizedBox && w.child is SingleChildScrollView,
  ),
);

Future<void> _openAdvanced(WidgetTester tester, double width) async {
  _setWindow(tester, width);
  final services = await PlayerScreenHarness.createServices();
  addTearDown(services.settings.dispose);
  services.settings.advancedPlaybackToolsEnabled = true;
  final controller = AdvancedPlaybackController(
    settings: services.settings,
    player: HeadlessPlayerService(),
  );
  await controller.setSource(PlayableSource.file('/e2e/policies.mp3'));
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AdvancedPlaybackDialog(
              controller: controller,
              settings: services.settings,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _openMediaInfo(WidgetTester tester, double width) async {
  _setWindow(tester, width);
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const MediaInfoDialog(
              fields: [
                MediaInfoField(label: 'Source', value: '/media/example.mp3'),
                MediaInfoField(label: 'Type', value: 'Local file'),
              ],
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _expectDialogFits(WidgetTester tester, double window, double declared) {
  expect(tester.takeException(), isNull);
  final box = tester.widget<SizedBox>(_dialogContentBox);
  expect(box.width, declared);
  expect(tester.getSize(_dialogContentBox).width, lessThanOrEqualTo(window));
}

Widget _transport(double speed) => TransportControls(
  isPlaying: true,
  volume: 50,
  hasMedia: true,
  speed: speed,
  loopMode: LoopMode.none,
  recentFiles: const [],
  onPlayPause: () {},
  onStop: () {},
  onOpenFile: () {},
  onOpenFolder: () {},
  onOpenUrl: () {},
  onReopenLast: () {},
  onVolumeChanged: (_) {},
  onLoopModeChanged: (_) {},
  onRecentFileSelected: (_) {},
  onSettingsPressed: () {},
  onPrevious: () {},
  onNext: () {},
  onToggleQueue: () {},
  onMoreActions: () {},
  onToggleMute: () {},
  onCycleSpeed: () {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'policies',
    expectedIds: [
      'M24.1',
      'M24.2',
      'M24.3',
      'M24.4',
      'M24.5',
      'M28.1',
      'M28.2',
      'M28.3',
      'M28.4',
      'M31.10',
      'M32.1',
      'M32.2',
      'M32.3',
      'M32.4',
      'M33.1',
      'M33.2',
      'M33.3',
      'M33.4',
      'M33.5',
    ],
  );
  tearDownAll(report.write);

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);

  group('Finding 24 speed label', () {
    test('M24.1 off-preset rate shows the real rate', () {
      expect(PlaybackSpeedPolicy.formatLabel(1.1), '1.1×');
      expect(PlaybackSpeedPolicy.formatLabel(1.1), isNot('1×'));
      expect(PlaybackSpeedPolicy.formatLabel(1.1), isNot('1.25×'));
      report.pass('M24.1');
    });

    test('M24.2 exact presets keep their output', () {
      final expected = {
        0.5: '0.5×',
        0.75: '0.75×',
        1.0: '1×',
        1.25: '1.25×',
        1.5: '1.5×',
        2.0: '2×',
      };
      for (final entry in expected.entries) {
        expect(
          PlaybackSpeedPolicy.formatLabel(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
      report.pass('M24.2');
    });

    test('M24.3 trailing zeros trimmed, at most two decimals', () {
      expect(PlaybackSpeedPolicy.formatLabel(0.25), '0.25×');
      expect(PlaybackSpeedPolicy.formatLabel(1.126), '1.13×');
      expect(PlaybackSpeedPolicy.formatLabel(1.999), '2×');
      expect(PlaybackSpeedPolicy.formatLabel(4.0), '4×');
      expect(PlaybackSpeedPolicy.formatLabel(1.3333), '1.33×');
      expect(PlaybackSpeedPolicy.formatLabel(1.10), '1.1×');
      report.pass('M24.3');
    });

    test('M24.4 non-finite rate does not throw', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(PlaybackSpeedPolicy.formatLabel(value), isNotEmpty);
      }
      report.pass('M24.4');
    });

    testWidgets('M24.5 transport speed chip shows the real rate', (
      tester,
    ) async {
      _setWindow(tester, 1200);
      await tester.pumpWidget(_app(Scaffold(body: _transport(1.1))));
      final chipText = find.descendant(
        of: find.byKey(const Key('transport-speed-chip')),
        matching: find.text('1.1×'),
      );
      expect(chipText, findsOneWidget);
      report.pass('M24.5');
    });
  });

  group('Finding 28 dialog widths', () {
    testWidgets('M28.1 advanced dialog fits a 400 px window', (tester) async {
      await _openAdvanced(tester, 400);
      _expectDialogFits(tester, 400, 352);
      report.pass('M28.1');
    });

    testWidgets('M28.2 media info dialog fits a 400 px window', (tester) async {
      await _openMediaInfo(tester, 400);
      _expectDialogFits(tester, 400, 352);
      report.pass('M28.2');
    });

    testWidgets('M28.3 wide window keeps 520', (tester) async {
      await _openAdvanced(tester, 1200);
      _expectDialogFits(tester, 1200, 520);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _openMediaInfo(tester, 1200);
      _expectDialogFits(tester, 1200, 520);
      report.pass('M28.3');
    });

    testWidgets('M28.4 minimum window and narrower use the clamp', (
      tester,
    ) async {
      await _openAdvanced(tester, 480);
      _expectDialogFits(tester, 480, 432);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      await _openMediaInfo(tester, 320);
      _expectDialogFits(tester, 320, 280);
      report.pass('M28.4');
    });
  });

  group('Finding 31 equalizer presets', () {
    test('M31.10 preset labels come from localization', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      for (final preset in kEqPresets) {
        expect(eqPresetLabel(l10n, preset.id), isNotEmpty, reason: preset.id);
      }
      expect(eqPresetLabel(l10n, 'not-a-preset'), isNotNull);
      report.pass('M31.10');
    });
  });

  group('Finding 32 extensions', () {
    test('M32.1 supported set contains the new extensions', () {
      for (final ext in [..._newAudio, ..._newVideo]) {
        expect(PlayerPathUtils.supportedExtensions, contains(ext));
        expect(PlayerPathUtils.isSupportedExtension(ext), isTrue, reason: ext);
        expect(
          PlayerPathUtils.isSupportedExtension(ext.toUpperCase()),
          isTrue,
          reason: ext,
        );
      }
      report.pass('M32.1');
    });

    test('M32.2 audio and video sets classify them correctly', () {
      for (final ext in _newAudio) {
        expect(PlayerPathUtils.audioExtensions, contains(ext));
        expect(PlayerPathUtils.isAudioExtension(ext), isTrue, reason: ext);
      }
      for (final ext in _newVideo) {
        expect(PlayerPathUtils.videoExtensions, contains(ext));
        expect(PlayerPathUtils.isAudioExtension(ext), isFalse, reason: ext);
      }
      expect(
        PlayerPathUtils.audioExtensions.intersection(
          PlayerPathUtils.videoExtensions,
        ),
        isEmpty,
      );
      report.pass('M32.2');
    });

    test(
      'M32.3 folder scanner returns files with the new extensions',
      () async {
        final dir = Directory.systemTemp.createTempSync('dacx_audit9_ext_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final all = [..._newAudio, ..._newVideo];
        for (final ext in all) {
          File('${dir.path}${Platform.pathSeparator}clip.$ext')
              .writeAsStringSync('x');
        }
        File('${dir.path}${Platform.pathSeparator}notes.txt')
            .writeAsStringSync('x');
        final result = await MediaFolderScanner.scan(dir.path);
        final found = result.paths
            .map((path) => path.split(RegExp(r'[\\/]')).last.split('.').last)
            .toSet();
        expect(found, all.toSet());
        expect(result.skipped, 1);
        report.pass('M32.3');
      },
    );

    test('M32.4 drop batch policy keeps the new extensions', () {
      final raw = [
        for (final ext in [..._newAudio, ..._newVideo]) '/media/clip.$ext',
      ];
      final batch = DropPathBatchPolicy.fromRawPaths(
        rawPaths: raw,
        windows: false,
      );
      expect(batch.paths, raw);
      expect(batch.skippedCount, 0);
      for (final path in batch.paths) {
        final ext = path.split('.').last;
        expect(PlayerPathUtils.isSupportedExtension(ext), isTrue);
      }
      report.pass('M32.4');
    });
  });

  group('Finding 33 duration formatter', () {
    const hour = Duration(hours: 1, minutes: 2, seconds: 3);

    test('M33.1 formatDuration output', () {
      expect(PlayerController.formatDuration(Duration.zero), '00:00');
      expect(
        PlayerController.formatDuration(const Duration(seconds: 7)),
        '00:07',
      );
      expect(
        PlayerController.formatDuration(
          const Duration(minutes: 59, seconds: 59),
        ),
        '59:59',
      );
      expect(
        PlayerController.formatDuration(const Duration(hours: 1)),
        '1:00:00',
      );
      expect(PlayerController.formatDuration(hour), '1:02:03');
      expect(
        PlayerController.formatDuration(const Duration(hours: 12, seconds: 5)),
        '12:00:05',
      );
      expect(
        PlayerController.formatDuration(const Duration(hours: 100)),
        '100:00:00',
      );
      report.pass('M33.1');
    });

    testWidgets('M33.2 seek slider semantics use formatDuration', (
      tester,
    ) async {
      _setWindow(tester, 800);
      const position = Duration(minutes: 5, seconds: 9);
      const duration = Duration(hours: 2, minutes: 3, seconds: 4);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SizedBox(
              width: 400,
              child: SeekSliderWithHover(
                position: position,
                duration: duration,
                onSeekStart: () {},
                onSeekChange: (_) {},
                onSeekEnd: (_) {},
              ),
            ),
          ),
        ),
      );
      final value = tester.getSemantics(find.byType(SeekSliderWithHover)).value;
      expect(value, contains(PlayerController.formatDuration(position)));
      expect(value, contains(PlayerController.formatDuration(duration)));
      report.pass('M33.2');
    });

    testWidgets('M33.3 OSD overlay time uses formatDuration', (tester) async {
      _setWindow(tester, 800);
      const position = Duration(minutes: 1, seconds: 5);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: OsdOverlay(
              title: 'Title',
              position: position,
              duration: hour,
              visible: true,
              transientMessage: null,
            ),
          ),
        ),
      );
      final expected =
          '${PlayerController.formatDuration(position)} / '
          '${PlayerController.formatDuration(hour)}';
      expect(find.text(expected), findsOneWidget);
      report.pass('M33.3');
    });

    testWidgets('M33.4 marker subtitle uses formatDuration', (tester) async {
      _setWindow(tester, 1200);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      services.settings.advancedPlaybackToolsEnabled = true;
      final controller = AdvancedPlaybackController(
        settings: services.settings,
        player: HeadlessPlayerService(),
      );
      await controller.setSource(PlayableSource.file('/e2e/markers.mp3'));
      controller.setPosition(hour);
      controller.addMarker(label: 'Long');
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AdvancedPlaybackDialog(
                  controller: controller,
                  settings: services.settings,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(PlayerController.formatDuration(hour)), findsOneWidget);
      report.pass('M33.4');
    });

    test('M33.5 no private duration formatter remains', () {
      for (final path in [
        'lib/widgets/seek_slider.dart',
        'lib/widgets/osd_overlay.dart',
        'lib/widgets/advanced_playback_dialog.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          RegExp(r'String\s+_(fmt|format)\s*\(\s*Duration').hasMatch(source),
          isFalse,
          reason: path,
        );
        expect(source, contains('PlayerController.formatDuration'));
      }
      report.pass('M33.5');
    });
  });
}
