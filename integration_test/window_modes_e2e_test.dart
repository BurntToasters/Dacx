import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';

const _schema = 'dacx.e2e.window-modes.v1';
const _modeIds = ['M48.1', 'M48.2', 'M48.3', 'M48.4', 'M48.5', 'M48.6'];
const _miniLayoutKey = ValueKey('mini-player-layout');
const _titleOverlayKey = ValueKey('fullscreen-title-overlay');
const _dockOverlayKey = ValueKey('fullscreen-dock-overlay');
const _miniSize = Size(480, 320);
const _sizeTolerance = 4.0;
const _playbackTimeout = Duration(seconds: 15);
const _transitionTimeout = Duration(seconds: 5);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real window enters and leaves mini-player and fullscreen', (
    tester,
  ) async {
    final fixture = Platform.environment['DACX_E2E_FIXTURE'];
    final version = Platform.environment['DACX_E2E_VERSION'];
    final runId = Platform.environment['DACX_E2E_RUN_ID'];
    final reportPath = Platform.environment['DACX_E2E_REPORT'];
    final audioOutput = Platform.environment['DACX_E2E_AUDIO_OUTPUT']?.trim();
    if (fixture == null || fixture.trim().isEmpty) {
      fail('DACX_E2E_FIXTURE is required for window modes E2E');
    }
    if (version == null || version.trim().isEmpty) {
      fail('DACX_E2E_VERSION is required for window modes E2E');
    }
    if (runId == null || runId.trim().isEmpty) {
      fail('DACX_E2E_RUN_ID is required for window modes E2E');
    }
    if (!File(fixture).existsSync()) fail('Fixture does not exist: $fixture');

    final hardGeometry = Platform.isWindows;

    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.show();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final debugLog = DebugLogService(isEnabled: () => false);
    final updates = UpdateService(
      debugLog: debugLog,
      debugSource: 'window_modes_e2e',
      httpGet: (_, {headers}) async => throw StateError('offline in E2E'),
    );
    final player = PlayerService();
    final audioOutputSet = audioOutput == null || audioOutput.isEmpty
        ? true
        : await player.setProperty('ao', audioOutput);
    var duration = Duration.zero;
    var playing = false;
    final subscriptions = <StreamSubscription<dynamic>>[
      player.durationStream.listen((value) => duration = value),
      player.playingStream.listen((value) => playing = value),
    ];

    final checks = <_Check>[];
    final steps = <String, Map<String, Object?>>{};
    void check(
      String? mode,
      String name,
      bool passed, {
      bool recordOnly = false,
    }) {
      checks.add(_Check(mode, name, passed, recordOnly));
    }

    var completed = false;
    var passed = false;
    try {
      runApp(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayerScreen(
            settings: settings,
            debugLog: debugLog,
            updateService: updates,
            playerService: player,
            initialFile: fixture,
          ),
        ),
      );

      final playbackDeadline = DateTime.now().add(_playbackTimeout);
      while ((duration <= Duration.zero || !playing) &&
          DateTime.now().isBefore(playbackDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      check(null, 'fixturePlaying', duration > Duration.zero && playing);

      final initial = await _snapshot();
      steps['initial'] = {
        ...initial.toJson(),
        'alwaysOnTopSetting': settings.alwaysOnTop,
        'playing': playing,
        'durationMs': duration.inMilliseconds,
      };

      await _pressMiniShortcut(tester);
      final miniEnter = await _settle(
        tester,
        (s) => _miniReady(s, hardGeometry),
      );
      final miniEntered = miniEnter.miniLayout;
      steps['miniEnter'] = {
        ...miniEnter.toJson(),
        'miniSupported': miniEntered,
      };
      check(
        'M48.1',
        'miniLayoutPresent',
        miniEntered,
        recordOnly: _recordOnly(hardGeometry, miniEntered),
      );
      check(
        'M48.2',
        'miniWindowSize',
        _sized(miniEnter.size, _miniSize),
        recordOnly: !hardGeometry,
      );
      check(
        'M48.2',
        'miniAlwaysOnTop',
        miniEnter.alwaysOnTop,
        recordOnly: !hardGeometry,
      );

      if (hardGeometry || miniEntered) {
        await _pressMiniShortcut(tester);
      }
      final miniExit = await _settle(
        tester,
        (s) =>
            !s.miniLayout &&
            (!hardGeometry || _windowedReady(s, initial, settings)),
      );
      steps['miniExit'] = miniExit.toJson();
      check(
        'M48.3',
        'miniLayoutAbsent',
        !miniExit.miniLayout,
        recordOnly: _recordOnly(hardGeometry, miniEntered),
      );
      check(
        'M48.3',
        'restoredWindowSize',
        _sized(miniExit.size, initial.size),
        recordOnly: !hardGeometry,
      );
      check(
        'M48.3',
        'alwaysOnTopMatchesSetting',
        miniExit.alwaysOnTop == settings.alwaysOnTop,
        recordOnly: !hardGeometry,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      final fullscreenEnter = await _settle(tester, _fullscreenReady);
      final fullscreenEntered = fullscreenEnter.fullscreen;
      steps['fullscreenEnter'] = {
        ...fullscreenEnter.toJson(),
        'fullscreenSupported': fullscreenEntered,
      };
      check(
        'M48.4',
        'fullscreenOverlaysConsistent',
        _overlaysMatchFullscreen(fullscreenEnter),
      );
      check(
        'M48.4',
        'fullscreenOverlaysPresent',
        fullscreenEnter.titleOverlay && fullscreenEnter.dockOverlay,
        recordOnly: _recordOnly(hardGeometry, fullscreenEntered),
      );
      check(
        'M48.4',
        'fullscreenWindow',
        fullscreenEntered,
        recordOnly: !hardGeometry,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      final fullscreenExit = await _settle(tester, _windowedOverlaysGone);
      steps['fullscreenExit'] = fullscreenExit.toJson();
      check(
        'M48.5',
        'fullscreenOverlaysConsistent',
        _overlaysMatchFullscreen(fullscreenExit),
      );
      check(
        'M48.5',
        'fullscreenOverlaysAbsent',
        !fullscreenExit.titleOverlay && !fullscreenExit.dockOverlay,
        recordOnly: _recordOnly(hardGeometry, fullscreenEntered),
      );
      check(
        'M48.5',
        'windowedAfterEscape',
        !fullscreenExit.fullscreen,
        recordOnly: !hardGeometry,
      );

      await _pressMiniShortcut(tester);
      final miniBeforeFullscreen = await _settle(
        tester,
        (s) => _miniReady(s, hardGeometry),
      );
      final miniBeforeEntered = miniBeforeFullscreen.miniLayout;
      steps['miniBeforeFullscreen'] = {
        ...miniBeforeFullscreen.toJson(),
        'miniSupported': miniBeforeEntered,
      };
      check(
        'M48.6',
        'miniLayoutPresentBeforeFullscreen',
        miniBeforeEntered,
        recordOnly: _recordOnly(hardGeometry, miniBeforeEntered),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      final miniThenFullscreen = await _settle(
        tester,
        (s) => !s.miniLayout && _fullscreenReady(s),
      );
      final fullscreenAfterMini = miniThenFullscreen.fullscreen;
      steps['miniThenFullscreen'] = {
        ...miniThenFullscreen.toJson(),
        'fullscreenSupported': fullscreenAfterMini,
      };
      check(
        'M48.6',
        'fullscreenOverlaysConsistent',
        _overlaysMatchFullscreen(miniThenFullscreen),
      );
      check(
        'M48.6',
        'miniLayoutAbsentWhenFullscreen',
        !miniThenFullscreen.fullscreen || !miniThenFullscreen.miniLayout,
      );
      check(
        'M48.6',
        'miniLayoutAbsentInFullscreen',
        !miniThenFullscreen.miniLayout,
        recordOnly: _recordOnly(hardGeometry, fullscreenAfterMini),
      );
      check(
        'M48.6',
        'fullscreenOverlaysPresent',
        miniThenFullscreen.titleOverlay && miniThenFullscreen.dockOverlay,
        recordOnly: _recordOnly(hardGeometry, fullscreenAfterMini),
      );
      check(
        'M48.6',
        'fullscreenWindow',
        fullscreenAfterMini,
        recordOnly: !hardGeometry,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      final miniThenWindowed = await _settle(tester, _windowedOverlaysGone);
      steps['miniThenWindowed'] = miniThenWindowed.toJson();
      check(
        'M48.5',
        'overlaysMatchFullscreenAfterMiniEscape',
        _overlaysMatchFullscreen(miniThenWindowed),
      );
      check(
        'M48.5',
        'overlaysAbsentAfterMiniFullscreen',
        !miniThenWindowed.titleOverlay && !miniThenWindowed.dockOverlay,
        recordOnly: _recordOnly(hardGeometry, fullscreenAfterMini),
      );
      check(
        'M48.5',
        'windowedAfterMiniFullscreen',
        !miniThenWindowed.fullscreen,
        recordOnly: !hardGeometry,
      );
      completed = true;
    } finally {
      await _restoreWindow(tester);
      passed =
          completed &&
          checks.where((c) => !c.recordOnly).every((c) => c.passed);
      final passedModes = [
        for (final id in _modeIds)
          if (_modePassed(checks, id)) id,
      ];
      final skippedModes = [
        for (final id in _modeIds)
          if (_modeSkipped(checks, id)) id,
      ];
      final report = <String, Object?>{
        'schema': _schema,
        'version': version,
        'runId': runId,
        'platform': Platform.operatingSystem,
        'status': passed ? 'passed' : 'failed',
        'hardGeometry': hardGeometry,
        'audioOutputSet': audioOutputSet,
        'passedModes': passedModes,
        'skippedModes': skippedModes,
        'checks': [for (final c in checks) c.toJson()],
        'steps': steps,
      };
      final output = _reportFile(reportPath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      debugPrint('DACX_E2E_REPORT_JSON ${jsonEncode(report)}');

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      settings.dispose();
    }
    if (!passed) {
      fail('Window modes E2E failed; report: ${_reportFile(reportPath).path}');
    }
  });
}

final class _Check {
  const _Check(this.mode, this.name, this.passed, this.recordOnly);

  final String? mode;
  final String name;
  final bool passed;
  final bool recordOnly;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'name': name,
    'passed': passed,
    'recordOnly': recordOnly,
  };
}

final class _WindowSnapshot {
  const _WindowSnapshot({
    required this.miniLayout,
    required this.titleOverlay,
    required this.dockOverlay,
    required this.size,
    required this.alwaysOnTop,
    required this.fullscreen,
  });

  final bool miniLayout;
  final bool titleOverlay;
  final bool dockOverlay;
  final Size size;
  final bool alwaysOnTop;
  final bool fullscreen;

  Map<String, Object?> toJson() => {
    'miniLayout': miniLayout,
    'fullscreenTitleOverlay': titleOverlay,
    'fullscreenDockOverlay': dockOverlay,
    'width': size.width,
    'height': size.height,
    'alwaysOnTop': alwaysOnTop,
    'fullscreen': fullscreen,
  };
}

Future<_WindowSnapshot> _snapshot() async {
  final size = await windowManager.getSize();
  final alwaysOnTop = await windowManager.isAlwaysOnTop();
  final fullscreen = await windowManager.isFullScreen();
  return _WindowSnapshot(
    miniLayout: find.byKey(_miniLayoutKey).evaluate().isNotEmpty,
    titleOverlay: find.byKey(_titleOverlayKey).evaluate().isNotEmpty,
    dockOverlay: find.byKey(_dockOverlayKey).evaluate().isNotEmpty,
    size: size,
    alwaysOnTop: alwaysOnTop,
    fullscreen: fullscreen,
  );
}

Future<_WindowSnapshot> _settle(
  WidgetTester tester,
  bool Function(_WindowSnapshot snapshot) done,
) async {
  final deadline = DateTime.now().add(_transitionTimeout);
  var snapshot = await _snapshot();
  while (!done(snapshot) && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    snapshot = await _snapshot();
  }
  return snapshot;
}

Future<void> _restoreWindow(WidgetTester tester) async {
  try {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    final current = await _snapshot();
    if (current.miniLayout) {
      await _pressMiniShortcut(tester);
      await _settle(tester, (s) => !s.miniLayout);
    }
  } catch (error) {
    debugPrint('DACX_E2E_RESTORE_FAILED $error');
  }
}

Future<void> _pressMiniShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

bool _sized(Size actual, Size expected) =>
    (actual.width - expected.width).abs() <= _sizeTolerance &&
    (actual.height - expected.height).abs() <= _sizeTolerance;

bool _recordOnly(bool hardGeometry, bool observed) =>
    !hardGeometry && !observed;

bool _miniReady(_WindowSnapshot s, bool hardGeometry) =>
    s.miniLayout &&
    (!hardGeometry || (_sized(s.size, _miniSize) && s.alwaysOnTop));

bool _windowedReady(
  _WindowSnapshot s,
  _WindowSnapshot initial,
  SettingsService settings,
) => _sized(s.size, initial.size) && s.alwaysOnTop == settings.alwaysOnTop;

bool _fullscreenReady(_WindowSnapshot s) =>
    s.titleOverlay && s.dockOverlay && s.fullscreen;

bool _windowedOverlaysGone(_WindowSnapshot s) =>
    !s.titleOverlay && !s.dockOverlay && !s.fullscreen;

bool _overlaysMatchFullscreen(_WindowSnapshot s) =>
    s.titleOverlay == s.fullscreen && s.dockOverlay == s.fullscreen;

bool _modePassed(List<_Check> checks, String id) {
  final owned = checks.where((c) => c.mode == id).toList();
  return owned.isNotEmpty && owned.every((c) => !c.recordOnly && c.passed);
}

bool _modeSkipped(List<_Check> checks, String id) {
  final owned = checks.where((c) => c.mode == id).toList();
  return owned.any((c) => c.recordOnly) &&
      owned.where((c) => !c.recordOnly).every((c) => c.passed);
}

File _reportFile(String? reportPath) {
  if (reportPath == null || reportPath.trim().isEmpty) {
    return File(
      'test-results/e2e/${Platform.operatingSystem}/window-modes.json',
    );
  }
  return File(
    '${File(reportPath).parent.path}${Platform.pathSeparator}window-modes.json',
  );
}
