import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/playback/player_controller.dart';
import 'package:dacx/playback/playlist_advance_policy.dart';
import 'package:dacx/playback/sleep_timer_controller.dart';
import 'package:dacx/screens/player/widgets/player_bottom_dock.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/playlist_service.dart';
import 'package:dacx/services/seek_preview_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/settings_row.dart';
import 'package:dacx/widgets/transport_controls.dart';

import '../support/audit9_report.dart';

final report = Audit9Report(
  'transport-settings',
  expectedIds: const [
    'M11.1',
    'M11.2',
    'M11.3',
    'M11.4',
    'M11.5',
    'M11.6',
    'M11.7',
    'M11.8',
    'M25.1',
    'M25.2',
    'M25.3',
    'M25.4',
    'M25.5',
    'M25.6',
    'M25.7',
  ],
);

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
    ],
  );
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: _theme(),
  home: Scaffold(body: child),
);

void _size(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

TransportControls _controls({
  double volume = 50,
  bool hasMedia = true,
  bool? canGoPrevious,
  bool? canGoNext,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
}) {
  return TransportControls(
    isPlaying: false,
    volume: volume,
    hasMedia: hasMedia,
    speed: 1.0,
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
    onPrevious: onPrevious ?? () {},
    onNext: onNext ?? () {},
    onToggleQueue: () {},
    onMoreActions: (_) {},
    onToggleMute: () {},
    onCycleSpeed: () {},
    canGoPrevious: canGoPrevious,
    canGoNext: canGoNext,
  );
}

VoidCallback? _pressed(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed;

Future<({SettingsService settings, DebugLogService debugLog})> _services({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final debugLog = DebugLogService(isEnabled: () => settings.debugModeEnabled);
  return (settings: settings, debugLog: debugLog);
}

Future<SettingsService> _pumpSettings(
  WidgetTester tester, {
  required double width,
  Map<String, Object> initial = const {},
  void Function(SettingsService settings)? prepare,
}) async {
  _size(tester, width, 700);
  final svc = await _services(initial: initial);
  prepare?.call(svc.settings);
  final updates = UpdateService(debugLog: svc.debugLog, debugSource: 'e2e');
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _theme(),
      home: SettingsScreen(
        settings: svc.settings,
        debugLog: svc.debugLog,
        updateService: updates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return svc.settings;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300);
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SettingsScreen)));

List<({String title, Finder control})> _wideRows(AppLocalizations l10n) => [
  (
    title: l10n.settingsPlaybackSpeed,
    control: find.byType(DropdownButton<double>),
  ),
  (
    title: l10n.settingsLoopMode,
    control: find.byType(SegmentedButton<LoopMode>),
  ),
  (
    title: l10n.settingsScreenshotDir,
    control: find.widgetWithText(TextButton, l10n.settingsChooseScreenshotDir),
  ),
  (
    title: l10n.settingsScreenshotFormat,
    control: find.byType(SegmentedButton<String>),
  ),
  (
    title: l10n.settingsHardwareAcceleration,
    control: find.byType(DropdownButton<String>),
  ),
  (title: l10n.settingsTheme, control: find.byType(SegmentedButton<ThemeMode>)),
  (
    title: l10n.settingsUpdateChannel,
    control: find.byType(SegmentedButton<UpdateChannel>),
  ),
  (
    title: l10n.settingsRecentFiles,
    control: find.widgetWithText(TextButton, l10n.actionClear),
  ),
];

AccentColor? _focusedAccent() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  AccentColor? found;
  context.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String>) {
      for (final ac in AccentColor.values) {
        if (key.value == 'accent-swatch-${ac.name}') {
          found = ac;
          return false;
        }
      }
    }
    return true;
  });
  return found;
}

Future<AccentColor> _tabToSwatch(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = _focusedAccent();
    if (focused != null) return focused;
  }
  fail('Tab never reached an accent swatch');
}

void main() {
  tearDownAll(report.write);

  group('Finding 11 policy', () {
    test('M11.1 empty queue disables both in every loop mode', () {
      for (final mode in LoopMode.values) {
        expect(
          PlaylistAdvancePolicy.canGoNext(
            queueLength: 0,
            loopMode: mode,
            hasNextInOrder: false,
          ),
          isFalse,
          reason: 'next $mode',
        );
        expect(
          PlaylistAdvancePolicy.canGoPrevious(
            queueLength: 0,
            loopMode: mode,
            hasPreviousInOrder: false,
          ),
          isFalse,
          reason: 'previous $mode',
        );
      }
      report.pass('M11.1');
    });

    test('M11.2 one item enables only with loop all', () {
      for (final mode in LoopMode.values) {
        final expected = mode == LoopMode.loop;
        expect(
          PlaylistAdvancePolicy.canGoNext(
            queueLength: 1,
            loopMode: mode,
            hasNextInOrder: false,
          ),
          expected,
          reason: 'next $mode',
        );
        expect(
          PlaylistAdvancePolicy.canGoPrevious(
            queueLength: 1,
            loopMode: mode,
            hasPreviousInOrder: false,
          ),
          expected,
          reason: 'previous $mode',
        );
      }
      report.pass('M11.2');
    });

    test('M11.3 edges follow order unless looping', () {
      for (final mode in [LoopMode.none, LoopMode.single]) {
        expect(
          PlaylistAdvancePolicy.canGoNext(
            queueLength: 3,
            loopMode: mode,
            hasNextInOrder: false,
          ),
          isFalse,
        );
        expect(
          PlaylistAdvancePolicy.canGoPrevious(
            queueLength: 3,
            loopMode: mode,
            hasPreviousInOrder: true,
          ),
          isTrue,
        );
        expect(
          PlaylistAdvancePolicy.canGoPrevious(
            queueLength: 3,
            loopMode: mode,
            hasPreviousInOrder: false,
          ),
          isFalse,
        );
        expect(
          PlaylistAdvancePolicy.canGoNext(
            queueLength: 3,
            loopMode: mode,
            hasNextInOrder: true,
          ),
          isTrue,
        );
      }
      for (final hasNext in [true, false]) {
        expect(
          PlaylistAdvancePolicy.canGoNext(
            queueLength: 3,
            loopMode: LoopMode.loop,
            hasNextInOrder: hasNext,
          ),
          isTrue,
        );
        expect(
          PlaylistAdvancePolicy.canGoPrevious(
            queueLength: 3,
            loopMode: LoopMode.loop,
            hasPreviousInOrder: hasNext,
          ),
          isTrue,
        );
      }
      report.pass('M11.3');
    });

    test('M11.4 real playlist drives the policy, shuffle included', () {
      final playlist = PlaylistService();
      bool next(LoopMode mode) => PlaylistAdvancePolicy.canGoNext(
        queueLength: playlist.length,
        loopMode: mode,
        hasNextInOrder: playlist.hasNext,
      );
      bool previous(LoopMode mode) => PlaylistAdvancePolicy.canGoPrevious(
        queueLength: playlist.length,
        loopMode: mode,
        hasPreviousInOrder: playlist.hasPrevious,
      );

      playlist.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
      expect(previous(LoopMode.none), isFalse);
      expect(next(LoopMode.none), isTrue);
      playlist.jumpTo(1);
      expect(previous(LoopMode.none), isTrue);
      expect(next(LoopMode.none), isTrue);
      playlist.jumpTo(2);
      expect(previous(LoopMode.none), isTrue);
      expect(next(LoopMode.none), isFalse);
      expect(next(LoopMode.loop), isTrue);

      playlist.jumpTo(0);
      playlist.setShuffle(true);
      expect(previous(LoopMode.none), isFalse);
      expect(next(LoopMode.none), isTrue);
      playlist.advance(1);
      playlist.advance(1);
      expect(previous(LoopMode.none), isTrue);
      expect(next(LoopMode.none), isFalse);
      expect(previous(LoopMode.loop), isTrue);
      expect(next(LoopMode.loop), isTrue);

      final single = PlaylistService()..replace(['/only.mp3']);
      expect(
        PlaylistAdvancePolicy.canGoNext(
          queueLength: single.length,
          loopMode: LoopMode.none,
          hasNextInOrder: single.hasNext,
        ),
        isFalse,
      );
      report.pass('M11.4');
    });
  });

  group('Finding 11 transport', () {
    testWidgets('M11.5 flags gate each button', (tester) async {
      for (final width in [1200.0, 480.0]) {
        _size(tester, width, 400);
        var previousCalls = 0;
        var nextCalls = 0;

        await tester.pumpWidget(
          _app(
            _controls(
              canGoPrevious: false,
              canGoNext: true,
              onPrevious: () => previousCalls++,
              onNext: () => nextCalls++,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(_pressed(tester, Icons.skip_previous), isNull, reason: '$width');
        expect(_pressed(tester, Icons.skip_next), isNotNull, reason: '$width');
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.skip_previous),
          warnIfMissed: false,
        );
        await tester.tap(find.widgetWithIcon(IconButton, Icons.skip_next));
        expect(previousCalls, 0, reason: '$width');
        expect(nextCalls, 1, reason: '$width');

        await tester.pumpWidget(
          _app(
            _controls(
              canGoPrevious: true,
              canGoNext: false,
              onPrevious: () => previousCalls++,
              onNext: () => nextCalls++,
            ),
          ),
        );
        expect(_pressed(tester, Icons.skip_previous), isNotNull);
        expect(_pressed(tester, Icons.skip_next), isNull);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.skip_previous));
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.skip_next),
          warnIfMissed: false,
        );
        expect(previousCalls, 1, reason: '$width');
        expect(nextCalls, 1, reason: '$width');
      }
      report.pass('M11.5');
    });

    testWidgets('M11.6 defaults keep hasMedia behavior', (tester) async {
      for (final width in [1200.0, 480.0]) {
        _size(tester, width, 400);

        await tester.pumpWidget(_app(_controls()));
        expect(_pressed(tester, Icons.skip_previous), isNotNull);
        expect(_pressed(tester, Icons.skip_next), isNotNull);

        await tester.pumpWidget(_app(_controls(hasMedia: false)));
        expect(_pressed(tester, Icons.skip_previous), isNull);
        expect(_pressed(tester, Icons.skip_next), isNull);

        await tester.pumpWidget(
          _app(
            _controls(hasMedia: false, canGoPrevious: true, canGoNext: true),
          ),
        );
        expect(_pressed(tester, Icons.skip_previous), isNull);
        expect(_pressed(tester, Icons.skip_next), isNull);
      }
      report.pass('M11.6');
    });

    testWidgets('M11.8 volume icon has three states', (tester) async {
      final expectations = <double, IconData>{
        0: Icons.volume_off,
        1: Icons.volume_down,
        25: Icons.volume_down,
        49: Icons.volume_down,
        50: Icons.volume_up,
        100: Icons.volume_up,
      };
      for (final width in [1200.0, 480.0]) {
        _size(tester, width, 400);
        for (final entry in expectations.entries) {
          await tester.pumpWidget(_app(_controls(volume: entry.key)));
          for (final icon in [
            Icons.volume_off,
            Icons.volume_down,
            Icons.volume_up,
          ]) {
            expect(
              find.byIcon(icon),
              icon == entry.value ? findsOneWidget : findsNothing,
              reason: '$width volume ${entry.key} icon $icon',
            );
          }
        }
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TransportControls)),
        );
        await tester.pumpWidget(_app(_controls(volume: 0)));
        expect(find.byTooltip(l10n.tooltipUnmute), findsOneWidget);
        await tester.pumpWidget(_app(_controls(volume: 30)));
        expect(find.byTooltip(l10n.tooltipMute), findsOneWidget);
      }
      report.pass('M11.8');
    });

    testWidgets('M11.7 dock derives the flags from the playlist', (
      tester,
    ) async {
      _size(tester, 1200, 600);
      final svc = await _services();
      final player = PlayerController();
      final playlist = PlaylistService()..replace(['/a.mp3', '/b.mp3']);
      final headless = HeadlessPlayerService();
      final advanced = AdvancedPlaybackController(
        settings: svc.settings,
        player: headless,
      );
      final sleep = SleepTimerController();
      addTearDown(() {
        advanced.dispose();
        sleep.dispose();
        playlist.dispose();
      });

      Widget dock({PlaylistService? withPlaylist}) => _app(
        ListenableBuilder(
          listenable: svc.settings,
          builder: (context, _) => PlayerBottomDock(
            sleepTimer: sleep,
            advancedPlayback: advanced,
            player: player,
            settings: svc.settings,
            seekPreviewService: SeekPreviewService(),
            hasMedia: true,
            playlist: withPlaylist,
            onSeekStart: () {},
            onSeekChange: (_) {},
            onSeekEnd: (_) {},
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
            onMoreActions: (_) {},
            onPrevious: () {},
            onNext: () {},
            onToggleQueue: () {},
            onToggleMute: () {},
            onCycleSpeed: () {},
          ),
        ),
      );

      await tester.pumpWidget(dock(withPlaylist: playlist));
      expect(_pressed(tester, Icons.skip_previous), isNull);
      expect(_pressed(tester, Icons.skip_next), isNotNull);

      playlist.jumpTo(1);
      await tester.pump();
      expect(_pressed(tester, Icons.skip_previous), isNotNull);
      expect(_pressed(tester, Icons.skip_next), isNull);

      svc.settings.loopMode = LoopMode.loop;
      await tester.pump();
      expect(_pressed(tester, Icons.skip_previous), isNotNull);
      expect(_pressed(tester, Icons.skip_next), isNotNull);

      svc.settings.loopMode = LoopMode.none;
      playlist.replace(['/only.mp3']);
      await tester.pump();
      expect(_pressed(tester, Icons.skip_previous), isNull);
      expect(_pressed(tester, Icons.skip_next), isNull);

      await tester.pumpWidget(dock());
      expect(_pressed(tester, Icons.skip_previous), isNotNull);
      expect(_pressed(tester, Icons.skip_next), isNotNull);
      report.pass('M11.7');
    });
  });

  group('Finding 25 settings rows', () {
    testWidgets('M25.1 SettingsRow stacks and spreads by width', (
      tester,
    ) async {
      for (final entry in {300.0: true, 900.0: false}.entries) {
        _size(tester, entry.key, 400);
        const titleKey = Key('row-title');
        const controlKey = Key('row-control');
        await tester.pumpWidget(
          _app(
            const SettingsRow(
              title: Text('Title', key: titleKey),
              subtitle: Text('Subtitle'),
              control: SizedBox(key: controlKey, width: 200, height: 40),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.byKey(titleKey));
        final control = tester.getRect(find.byKey(controlKey));
        final row = tester.getRect(find.byType(SettingsRow));
        expect(control.left, greaterThanOrEqualTo(row.left));
        expect(control.right, lessThanOrEqualTo(row.right));
        if (entry.value) {
          expect(control.top, greaterThanOrEqualTo(title.bottom));
        } else {
          expect(control.left, greaterThanOrEqualTo(title.right));
          expect(control.top, lessThan(title.bottom));
          expect(control.bottom, greaterThan(title.top));
        }
      }
      report.pass('M25.1');
    });

    testWidgets('M25.2 settings at 480 px lays out everywhere', (tester) async {
      await _pumpSettings(tester, width: 480);
      final l10n = _l10n(tester);
      for (final row in _wideRows(l10n)) {
        await _scrollTo(tester, find.text(row.title));
        expect(tester.takeException(), isNull, reason: row.title);
        expect(row.control, findsOneWidget, reason: row.title);
      }
      await tester.dragUntilVisible(
        find.text(l10n.settingsOpenSourceLicenses),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      report.pass('M25.2');
    });

    testWidgets('M25.3 titles keep width and controls stack at 480 px', (
      tester,
    ) async {
      await _pumpSettings(tester, width: 480);
      final l10n = _l10n(tester);
      for (final row in _wideRows(l10n)) {
        await _scrollTo(tester, find.text(row.title));
        final title = tester.getRect(find.text(row.title));
        final control = tester.getRect(row.control);
        expect(title.height, lessThan(30), reason: '${row.title} wrapped');
        expect(title.width, greaterThan(40), reason: row.title);
        expect(
          control.top,
          greaterThanOrEqualTo(title.bottom),
          reason: '${row.title} control not stacked',
        );
        expect(control.right, lessThanOrEqualTo(480), reason: row.title);
        expect(control.left, greaterThanOrEqualTo(0), reason: row.title);
      }
      report.pass('M25.3');
    });

    testWidgets('M25.4 titles and controls share a line at 1280 px', (
      tester,
    ) async {
      await _pumpSettings(tester, width: 1280);
      final l10n = _l10n(tester);
      for (final row in _wideRows(l10n)) {
        await _scrollTo(tester, find.text(row.title));
        expect(tester.takeException(), isNull, reason: row.title);
        final title = tester.getRect(find.text(row.title));
        final control = tester.getRect(row.control);
        expect(
          control.left,
          greaterThanOrEqualTo(title.right),
          reason: '${row.title} control overlaps title',
        );
        expect(control.top, lessThan(title.bottom), reason: row.title);
        expect(control.bottom, greaterThan(title.top), reason: row.title);
      }
      report.pass('M25.4');
    });

    testWidgets('M25.5 every setting keeps its behavior at 480 px', (
      tester,
    ) async {
      final dir = '${Directory.systemTemp.path}${Platform.pathSeparator}shots';
      final settings = await _pumpSettings(
        tester,
        width: 480,
        prepare: (s) {
          s.screenshotDir = dir;
          s.addRecentFile('/media/recent.mp3');
        },
      );
      final l10n = _l10n(tester);

      await _scrollTo(tester, find.byType(DropdownButton<double>));
      await tester.tap(find.byType(DropdownButton<double>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×').last);
      await tester.pumpAndSettle();
      expect(settings.speed, 1.5);

      await _scrollTo(tester, find.text(l10n.settingsLoopSingle));
      await tester.tap(find.text(l10n.settingsLoopSingle));
      await tester.pumpAndSettle();
      expect(settings.loopMode, LoopMode.single);

      final reset = find.widgetWithText(
        TextButton,
        l10n.settingsResetScreenshotDir,
      );
      await _scrollTo(tester, reset);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(settings.screenshotDir, isNull);
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      await _scrollTo(tester, find.text(l10n.settingsScreenshotFormatJpg));
      await tester.tap(find.text(l10n.settingsScreenshotFormatJpg));
      await tester.pumpAndSettle();
      expect(settings.screenshotFormat, 'jpg');

      await _scrollTo(tester, find.byType(DropdownButton<String>));
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHwDecOff).last);
      await tester.pumpAndSettle();
      expect(settings.hwDec, 'no');

      await _scrollTo(tester, find.text(l10n.settingsThemeLight));
      await tester.tap(find.text(l10n.settingsThemeLight));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.light);

      await _scrollTo(tester, find.text(l10n.settingsUpdateChannelBeta));
      await tester.tap(find.text(l10n.settingsUpdateChannelBeta));
      await tester.pumpAndSettle();
      expect(settings.updateChannel, UpdateChannel.beta);

      final clear = find.widgetWithText(TextButton, l10n.actionClear);
      await _scrollTo(tester, clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(settings.recentFiles, isEmpty);
      expect(tester.takeException(), isNull);
      report.pass('M25.5');
    });

    testWidgets('M25.6 accent swatches work from the keyboard', (tester) async {
      final settings = await _pumpSettings(
        tester,
        width: 480,
        initial: const {'appearance_accent': 'pink'},
      );
      expect(settings.accentColor, AccentColor.pink);
      final l10n = _l10n(tester);
      await _scrollTo(tester, find.text(l10n.settingsAccentColor));

      for (final ac in AccentColor.values) {
        expect(
          find.byKey(Key('accent-swatch-ring-${ac.name}')),
          findsNothing,
          reason: 'ring before focus ${ac.name}',
        );
      }

      final first = await _tabToSwatch(tester);
      expect(
        find.byKey(Key('accent-swatch-ring-${first.name}')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(settings.accentColor, first);
      expect(first, isNot(AccentColor.pink));

      final second = await _tabToSwatch(tester);
      expect(second, isNot(first));
      expect(find.byKey(Key('accent-swatch-ring-${first.name}')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(settings.accentColor, second);
      report.pass('M25.6');
    });

    testWidgets('M25.7 accent swatch semantics and pointer tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final settings = await _pumpSettings(
        tester,
        width: 480,
        initial: const {'appearance_accent': 'teal'},
      );
      final l10n = _l10n(tester);
      await _scrollTo(tester, find.text(l10n.settingsAccentColor));

      final teal = tester.getSemantics(
        find.bySemanticsLabel(l10n.semanticsAccentColor(l10n.accentColorTeal)),
      );
      expect(
        teal,
        isSemantics(
          label: l10n.semanticsAccentColor(l10n.accentColorTeal),
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      final blueLabel = l10n.semanticsAccentColor(l10n.accentColorBlue);
      final blue = tester.getSemantics(find.bySemanticsLabel(blueLabel));
      expect(
        blue,
        isSemantics(
          label: l10n.semanticsAccentColor(l10n.accentColorBlue),
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
        ),
      );

      await tester.tap(find.byKey(const Key('accent-swatch-blue')));
      await tester.pumpAndSettle();
      expect(settings.accentColor, AccentColor.blue);
      expect(
        tester.getSemantics(find.bySemanticsLabel(blueLabel)),
        isSemantics(isSelected: true, hasSelectedState: true),
      );
      handle.dispose();
      report.pass('M25.7');
    });
  });
}
