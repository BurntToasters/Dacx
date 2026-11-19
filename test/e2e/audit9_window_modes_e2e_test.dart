import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/l10n/app_localizations_en.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/player_window_controller.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/window_metrics.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/compact_exit_button.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _normalMinimum = Size(480, 320);
const _miniMinimum = Size(240, 135);
const _miniWindow = Size(480, 320);
const _preSize = Size(1200, 800);
const _prePosition = Offset(40, 60);
const _surfaceCenter = Offset(800, 500);
const _resizeMethods = {
  'setBounds',
  'setMinimumSize',
  'setAspectRatio',
  'setAlwaysOnTop',
};

final _l10n = AppLocalizationsEn();
final _clip = PlayableSource.file('/media/clip.mp4');

void _ignoreLog(
  String event, {
  DebugLogCategory category = DebugLogCategory.ui,
  String? message,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity severity = DebugSeverity.info,
}) {}

final class _Window {
  _Window(this.timeline);

  final List<String> timeline;
  final List<MethodCall> calls = <MethodCall>[];
  Size size = _preSize;
  Offset position = _prePosition;
  bool fullscreen = false;
  bool maximized = false;
  bool Function(MethodCall call)? fail;
  void Function(MethodCall call)? onCall;
  Completer<void>? gate;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PlayerScreenHarness.windowManagerChannel,
          handle,
        );
  }

  List<MethodCall> of(String method) => [
    for (final call in calls)
      if (call.method == method) call,
  ];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    timeline.add(call.method);
    onCall?.call(call);
    final pending = gate;
    if (call.method == 'getBounds' && pending != null) {
      await pending.future;
    }
    final failing = fail;
    if (failing != null && failing(call)) {
      throw PlatformException(code: 'window_call_failed');
    }
    switch (call.method) {
      case 'isMaximized':
        return maximized;
      case 'isMinimized':
        return false;
      case 'isFullScreen':
        return fullscreen;
      case 'setFullScreen':
        final args = call.arguments;
        fullscreen = args is bool
            ? args
            : (args as Map<Object?, Object?>)['isFullScreen'] as bool? ?? false;
        return null;
      case 'maximize':
        maximized = true;
        return null;
      case 'unmaximize':
        maximized = false;
        return null;
      case 'getBounds':
        return {
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        };
      case 'setBounds':
        final args = call.arguments as Map<Object?, Object?>;
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

final class _ControllerRig {
  _ControllerRig() : timeline = <String>[] {
    win = _Window(timeline)..install();
    controller = PlayerWindowController(
      isMounted: () => true,
      isDisposed: () => false,
      alwaysOnTop: () => alwaysOnTop,
      log: _ignoreLog,
      onFullscreenRejected: () {},
      onCompactModeChanged: (value) {
        modes.add(value);
        timeline.add('mode:$value');
      },
      onCompactGeometryHold: (value) {
        holds.add(value);
        timeline.add('hold:$value');
      },
      videoAspectRatio: () async => aspect,
    );
  }

  final List<String> timeline;
  late final _Window win;
  late final PlayerWindowController controller;
  final List<bool> modes = <bool>[];
  final List<bool> holds = <bool>[];
  bool alwaysOnTop = false;
  double? aspect = 16 / 9;

  Future<void> enter() => controller.toggleCompactMode();
}

final class _OsdRecorder extends ValueNotifier<String?> {
  _OsdRecorder() : super(null);

  final List<String> sets = <String>[];

  @override
  set value(String? next) {
    if (next != null) sets.add(next);
    super.value = next;
  }
}

List<double> _aspects(_Window win) => [
  for (final call in win.of('setAspectRatio'))
    ((call.arguments as Map)['aspectRatio'] as num).toDouble(),
];

List<Size> _minimums(_Window win) => [
  for (final call in win.of('setMinimumSize'))
    Size(
      ((call.arguments as Map)['width'] as num).toDouble(),
      ((call.arguments as Map)['height'] as num).toDouble(),
    ),
];

List<bool> _alwaysOnTop(_Window win) => [
  for (final call in win.of('setAlwaysOnTop'))
    (call.arguments as Map)['isAlwaysOnTop'] as bool,
];

T? _last<T>(List<T> values) => values.isEmpty ? null : values.last;

bool _setBoundsWidth(MethodCall call, num width) =>
    call.method == 'setBounds' &&
    (call.arguments as Map<Object?, Object?>)['width'] == width;

Future<void> _settle(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _toggleMini(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await _settle(tester);
}

Future<void> _emitWindowEvent(String eventName) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {'eventName': eventName}),
        ),
        (_) {},
      );
}

Future<_Window> _pumpPlayer(
  WidgetTester tester, {
  _Window? win,
  ValueChanged<bool>? onCompact,
  ValueNotifier<String?>? osd,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  final window = win ?? _Window(<String>[]);
  window.install();
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        extensions: [
          WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
        ],
      ),
      home: PlayerScreen(
        settings: services.settings,
        debugLog: services.debugLog,
        updateService: services.updates,
        playerService: HeadlessPlayerService(),
        headlessMediaSurface: true,
        initialLoadedSource: _clip,
        onCompactModeChanged: onCompact,
        osdMessageProbe: osd,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return window;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'window-modes',
    expectedIds: [
      for (var i = 1; i <= 6; i++) 'M39.$i',
      for (var i = 1; i <= 4; i++) 'M40.$i',
      for (var i = 1; i <= 7; i++) 'M41.$i',
      for (var i = 1; i <= 4; i++) 'M44.$i',
    ],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 39: mini-player entry geometry save', () {
    test(
      'M39.1 the hold is set before the first window call on enter',
      () async {
        final rig = _ControllerRig();
        await rig.enter();
        expect(rig.timeline.first, 'hold:true');
        expect(rig.holds, [true]);
        expect(rig.controller.compactMode, isTrue);
        report.pass('M39.1');
      },
    );

    test(
      'M39.2 the hold releases only after the pre-mini geometry is restored',
      () async {
        final rig = _ControllerRig();
        await rig.enter();
        rig.timeline.clear();
        await rig.controller.toggleCompactMode();
        final release = rig.timeline.indexOf('hold:false');
        final lastBounds = rig.timeline.lastIndexOf('setBounds');
        expect(release, greaterThanOrEqualTo(0));
        expect(release, greaterThan(lastBounds));
        expect(rig.win.size, _preSize);
        expect(rig.win.position, _prePosition);
        expect(rig.holds, [true, false]);
        report.pass('M39.2');
      },
    );

    test('M39.3 a failed enter releases the hold', () async {
      final rig = _ControllerRig();
      rig.win.fail = (call) => _setBoundsWidth(call, 480);
      await rig.enter();
      expect(rig.controller.compactMode, isFalse);
      expect(rig.holds, [true, false]);
      expect(rig.modes, isEmpty);
      report.pass('M39.3');
    });

    test(
      'M39.4 a failed exit keeps the hold while the mini size remains',
      () async {
        final rig = _ControllerRig();
        await rig.enter();
        rig.win.fail = (call) => _setBoundsWidth(call, 1200);
        await rig.controller.toggleCompactMode();
        expect(rig.controller.compactMode, isTrue);
        expect(rig.holds, [true]);
        expect(rig.modes, [true]);
        report.pass('M39.4');
      },
    );

    testWidgets(
      'M39.5 PlayerScreen forwards the hold before the enter resize',
      (tester) async {
        final reported = <bool>[];
        final win = _Window(<String>[]);
        await _pumpPlayer(tester, win: win, onCompact: reported.add);
        final atFirstResize = <List<bool>>[];
        win.onCall = (call) {
          if (atFirstResize.isEmpty && _resizeMethods.contains(call.method)) {
            atFirstResize.add(List<bool>.of(reported));
          }
        };
        await _toggleMini(tester);
        expect(find.byType(CompactExitButton), findsOneWidget);
        expect(atFirstResize, hasLength(1));
        expect(atFirstResize.single, contains(true));
        expect(reported, [true]);
        report.pass('M39.5');
      },
    );

    testWidgets('M39.6 the OSD message follows the real mode change once', (
      tester,
    ) async {
      final osd = _OsdRecorder();
      final win = _Window(<String>[]);
      await _pumpPlayer(tester, win: win, osd: osd);
      win.fail = (call) => _setBoundsWidth(call, 480);
      await _toggleMini(tester);
      expect(find.byType(CompactExitButton), findsNothing);
      expect(osd.sets, isEmpty);

      win.fail = null;
      final atFirstResize = <List<String>>[];
      win.onCall = (call) {
        if (atFirstResize.isEmpty && _resizeMethods.contains(call.method)) {
          atFirstResize.add(List<String>.of(osd.sets));
        }
      };
      await _toggleMini(tester);
      expect(atFirstResize.single, isEmpty);
      expect(osd.sets, [_l10n.osdMiniPlayerOn]);

      await _toggleMini(tester);
      expect(osd.sets, [_l10n.osdMiniPlayerOn, _l10n.osdMiniPlayerOff]);
      report.pass('M39.6');
    });
  });

  group('Finding 40: always-on-top setting while in the mini-player', () {
    test(
      'M40.1 a setting change in the mini-player makes no window call',
      () async {
        final rig = _ControllerRig();
        rig.alwaysOnTop = true;
        await rig.enter();
        rig.alwaysOnTop = false;
        rig.controller.applyAlwaysOnTop(false);
        await pumpEventQueue();
        expect(_alwaysOnTop(rig.win), [true]);
        report.pass('M40.1');
      },
    );

    test(
      'M40.2 a setting change during a toggle makes no window call',
      () async {
        final rig = _ControllerRig();
        rig.win.gate = Completer<void>();
        final pending = rig.enter();
        await pumpEventQueue();
        rig.controller.applyAlwaysOnTop(false);
        await pumpEventQueue();
        rig.win.gate!.complete();
        await pending;
        expect(_alwaysOnTop(rig.win), [true]);
        report.pass('M40.2');
      },
    );

    test('M40.3 leaving applies the setting value current at exit', () async {
      final rig = _ControllerRig();
      rig.alwaysOnTop = true;
      await rig.enter();
      rig.alwaysOnTop = false;
      rig.controller.applyAlwaysOnTop(false);
      await pumpEventQueue();
      await rig.controller.toggleCompactMode();
      expect(rig.controller.compactMode, isFalse);
      expect(_alwaysOnTop(rig.win).last, isFalse);
      report.pass('M40.3');
    });

    test('M40.4 the normal layout applies the new setting', () async {
      final rig = _ControllerRig();
      rig.controller.applyAlwaysOnTop(true);
      await pumpEventQueue();
      expect(_alwaysOnTop(rig.win), [true]);
      rig.controller.applyAlwaysOnTop(false);
      await pumpEventQueue();
      expect(_alwaysOnTop(rig.win), [true, false]);
      report.pass('M40.4');
    });
  });

  group('Finding 41: fullscreen while in the mini-player', () {
    test(
      'M41.1 fullscreen is requested only after the mini-player is left',
      () async {
        final rig = _ControllerRig();
        await rig.enter();
        final compactAtFullscreen = <bool>[];
        rig.win.onCall = (call) {
          if (call.method == 'setFullScreen') {
            compactAtFullscreen.add(rig.controller.compactMode);
          }
        };
        await rig.controller.toggleFullscreen();
        expect(compactAtFullscreen, [false]);
        expect(rig.win.fullscreen, isTrue);
        expect(rig.controller.isFullscreen, isTrue);
        report.pass('M41.1');
      },
    );

    test('M41.2 the pre-mini size, constraints and always-on-top return before fullscreen', () async {
      final rig = _ControllerRig();
      await rig.enter();
      final snapshots =
          <
            ({
              Size size,
              Offset position,
              Size? minimum,
              double? aspect,
              bool? alwaysOnTop,
            })
          >[];
      rig.win.onCall = (call) {
        if (call.method != 'setFullScreen') return;
        snapshots.add((
          size: rig.win.size,
          position: rig.win.position,
          minimum: _last(_minimums(rig.win)),
          aspect: _last(_aspects(rig.win)),
          alwaysOnTop: _last(_alwaysOnTop(rig.win)),
        ));
      };
      await rig.controller.toggleFullscreen();
      expect(snapshots, hasLength(1));
      final before = snapshots.single;
      expect(before.size, _preSize);
      expect(before.position, _prePosition);
      expect(before.minimum, _normalMinimum);
      expect(before.aspect, 0.0);
      expect(before.alwaysOnTop, isFalse);
      report.pass('M41.2');
    });

    test('M41.3 a failed leave does not enter fullscreen', () async {
      final rig = _ControllerRig();
      await rig.enter();
      rig.win.fail = (call) => _setBoundsWidth(call, 1200);
      await rig.controller.toggleFullscreen();
      expect(rig.win.of('setFullScreen'), isEmpty);
      expect(rig.controller.compactMode, isTrue);
      expect(rig.controller.isFullscreen, isFalse);
      expect(rig.holds, [true]);
      report.pass('M41.3');
    });

    test('M41.4 an OS fullscreen drops the mini-player mode', () async {
      final rig = _ControllerRig();
      await rig.enter();
      rig.controller.onEnterFullScreen();
      expect(rig.controller.compactMode, isFalse);
      expect(rig.controller.isFullscreen, isTrue);
      report.pass('M41.4');
    });

    test('M41.5 an OS fullscreen releases constraints, applies the setting and the hold', () async {
      final rig = _ControllerRig();
      rig.alwaysOnTop = true;
      await rig.enter();
      rig.alwaysOnTop = false;
      rig.controller.onEnterFullScreen();
      await pumpEventQueue();
      expect(_minimums(rig.win).last, _normalMinimum);
      expect(_aspects(rig.win).last, 0.0);
      expect(_alwaysOnTop(rig.win).last, isFalse);
      expect(rig.holds, [true, false]);
      report.pass('M41.5');
    });

    test('M41.6 leaving fullscreen restores the pre-mini size, position or maximized state', () async {
      final windowed = _ControllerRig();
      await windowed.enter();
      windowed.controller.onEnterFullScreen();
      await pumpEventQueue();
      windowed.controller.onLeaveFullScreen();
      await pumpEventQueue();
      expect(windowed.win.size, _preSize);
      expect(windowed.win.position, _prePosition);

      final maximized = _ControllerRig();
      maximized.win.maximized = true;
      await maximized.enter();
      maximized.controller.onEnterFullScreen();
      await pumpEventQueue();
      maximized.controller.onLeaveFullScreen();
      await pumpEventQueue();
      expect(maximized.win.of('maximize'), hasLength(1));
      expect(maximized.win.maximized, isTrue);
      report.pass('M41.6');
    });

    testWidgets(
      'M41.7 fullscreen shows the fullscreen layout and double-click leaves it',
      (tester) async {
        final win = await _pumpPlayer(tester);
        await _toggleMini(tester);
        win.fullscreen = true;
        await _emitWindowEvent('enter-full-screen');
        await _settle(tester);
        expect(find.byKey(const Key('mini-player-layout')), findsNothing);
        expect(
          find.byKey(const ValueKey('fullscreen-title-overlay')),
          findsOneWidget,
        );

        final mark = win.calls.length;
        await tester.tapAt(_surfaceCenter);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(_surfaceCenter);
        await _settle(tester);
        final methods = win.calls.skip(mark).map((c) => c.method).toSet();
        expect(methods, contains('setFullScreen'));
        expect(methods, isNot(contains('setAspectRatio')));
        expect(methods, isNot(contains('setMinimumSize')));
        expect(methods, isNot(contains('setBounds')));
        expect(win.fullscreen, isFalse);
        report.pass('M41.7');
      },
    );
  });

  group('Finding 44: duplicated minimum window sizes', () {
    test(
      'M44.1 WindowMetrics holds the 480x320, 240x135 and 480x320 sizes',
      () {
        expect(WindowMetrics.normalMinimumSize, _normalMinimum);
        expect(WindowMetrics.compactMinimumSize, _miniMinimum);
        expect(WindowMetrics.compactWindowSize, _miniWindow);
        report.pass('M44.1');
      },
    );

    test('M44.2 the controller size names alias WindowMetrics', () {
      expect(
        PlayerWindowController.normalMinimumSize,
        WindowMetrics.normalMinimumSize,
      );
      expect(
        PlayerWindowController.compactMinimumSize,
        WindowMetrics.compactMinimumSize,
      );
      expect(
        PlayerWindowController.compactWindowSize,
        WindowMetrics.compactWindowSize,
      );
      report.pass('M44.2');
    });

    test('M44.3 SettingsService minimums derive from WindowMetrics', () {
      expect(
        SettingsService.windowMinWidth,
        WindowMetrics.normalMinimumSize.width,
      );
      expect(
        SettingsService.windowMinHeight,
        WindowMetrics.normalMinimumSize.height,
      );
      report.pass('M44.3');
    });

    test('M44.4 no minimum size literal remains in the three files', () {
      final literal = RegExp(r'\b(480|320|240|135)\b');
      const files = [
        'lib/main.dart',
        'lib/services/settings_service.dart',
        'lib/screens/player/player_window_controller.dart',
      ];
      final offenders = <String>[
        for (final path in files)
          if (literal.hasMatch(File(path).readAsStringSync())) path,
      ];
      expect(offenders, isEmpty);
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('WindowMetrics.normalMinimumSize'),
      );
      report.pass('M44.4');
    });
  });
}
