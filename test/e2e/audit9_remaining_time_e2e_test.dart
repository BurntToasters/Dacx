import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/playback/player_controller.dart';
import 'package:dacx/playback/sleep_timer_controller.dart';
import 'package:dacx/screens/player/widgets/player_bottom_dock.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/seek_preview_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/seek_slider.dart';

import '../support/audit9_report.dart';

final report = Audit9Report(
  'remaining-time',
  expectedIds: const [
    'M36.1',
    'M36.2',
    'M36.3',
    'M36.4',
    'M36.5',
    'M36.6',
    'M36.7',
    'M36.8',
    'M36.9',
  ],
);

const _labelKey = Key('seek-duration-label');
const _prefKey = 'show_remaining_time';

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

class _Rig {
  _Rig(this.settings, this.prefs)
    : player = PlayerController(),
      sleep = SleepTimerController(),
      tick = ValueNotifier<int>(0) {
    advanced = AdvancedPlaybackController(
      settings: settings,
      player: HeadlessPlayerService(),
    );
  }

  final SettingsService settings;
  final SharedPreferences prefs;
  final PlayerController player;
  final SleepTimerController sleep;
  final ValueNotifier<int> tick;
  late final AdvancedPlaybackController advanced;

  void dispose() {
    advanced.dispose();
    sleep.dispose();
    tick.dispose();
  }

  Widget dock() => _app(
    ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, _, _) => PlayerBottomDock(
        sleepTimer: sleep,
        advancedPlayback: advanced,
        player: player,
        settings: settings,
        seekPreviewService: SeekPreviewService(),
        hasMedia: true,
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

  void setTimes(Duration position, Duration duration) {
    player.position = position;
    player.duration = duration;
    tick.value++;
  }
}

Future<_Rig> _rig(
  WidgetTester tester, {
  Map<String, Object> initial = const {},
  Duration position = const Duration(minutes: 2, seconds: 33),
  Duration duration = const Duration(minutes: 3, seconds: 45),
}) async {
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final rig = _Rig(SettingsService(prefs), prefs);
  addTearDown(rig.dispose);
  rig.player.position = position;
  rig.player.duration = duration;
  await tester.pumpWidget(rig.dock());
  await tester.pumpAndSettle();
  return rig;
}

String _labelText(WidgetTester tester) {
  final text = find.descendant(
    of: find.byKey(_labelKey),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(text).data!;
}

bool _focusInsideLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget.key == _labelKey) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabToLabel(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_focusInsideLabel()) return;
  }
  fail('Tab never reached the duration label');
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PlayerBottomDock)));

void main() {
  tearDownAll(report.write);

  testWidgets('M36.1 click toggles total and remaining', (tester) async {
    final rig = await _rig(tester);
    expect(_labelText(tester), '03:45');
    expect(find.text('-01:12'), findsNothing);

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:12');
    expect(rig.settings.showRemainingTime, isTrue);

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(_labelText(tester), '03:45');
    expect(rig.settings.showRemainingTime, isFalse);

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:12');
    expect(tester.takeException(), isNull);
    report.pass('M36.1');
  });

  testWidgets('M36.2 Enter and Space toggle from the keyboard', (tester) async {
    final rig = await _rig(tester);
    await _tabToLabel(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:12');
    expect(rig.settings.showRemainingTime, isTrue);
    expect(_focusInsideLabel(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_labelText(tester), '03:45');
    expect(rig.settings.showRemainingTime, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:12');
    report.pass('M36.2');
  });

  testWidgets('M36.3 choice persists across settings and dock', (tester) async {
    final rig = await _rig(tester);
    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool(_prefKey), isTrue);

    expect(SettingsService(rig.prefs).showRemainingTime, isTrue);

    final reloaded = _Rig(SettingsService(rig.prefs), rig.prefs);
    addTearDown(reloaded.dispose);
    reloaded.player.position = const Duration(minutes: 2, seconds: 33);
    reloaded.player.duration = const Duration(minutes: 3, seconds: 45);
    await tester.pumpWidget(reloaded.dock());
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:12');

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(rig.prefs.getBool(_prefKey), isFalse);
    expect(SettingsService(rig.prefs).showRemainingTime, isFalse);
    report.pass('M36.3');
  });

  testWidgets('M36.4 remaining is never negative and keeps the minus', (
    tester,
  ) async {
    final rig = await _rig(
      tester,
      initial: const {_prefKey: true},
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 3, seconds: 45),
    );
    expect(_labelText(tester), '-00:00');

    rig.setTimes(
      const Duration(minutes: 3, seconds: 45),
      const Duration(minutes: 3, seconds: 45),
    );
    await tester.pump();
    expect(_labelText(tester), '-00:00');

    rig.setTimes(Duration.zero, const Duration(hours: 1, minutes: 2));
    await tester.pump();
    expect(_labelText(tester), '-1:02:00');
    expect(_labelText(tester).startsWith('-'), isTrue);

    rig.setTimes(const Duration(hours: 2), const Duration(minutes: 3));
    await tester.pump();
    expect(_labelText(tester), '-00:00');
    report.pass('M36.4');
  });

  testWidgets('M36.5 unknown duration keeps output and flips stored mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    await tester.pumpWidget(
      _app(
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SeekDurationLabel(
            key: _labelKey,
            position: const Duration(seconds: 7),
            duration: Duration.zero,
            showRemaining: settings.showRemainingTime,
            onToggle: () =>
                settings.showRemainingTime = !settings.showRemainingTime,
          ),
        ),
      ),
    );
    expect(_labelText(tester), '00:00');

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(settings.showRemainingTime, isTrue);
    expect(_labelText(tester), '00:00');

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(settings.showRemainingTime, isFalse);
    expect(_labelText(tester), '00:00');
    expect(tester.takeException(), isNull);

    final rig = await _rig(
      tester,
      initial: const {_prefKey: true},
      position: Duration.zero,
      duration: Duration.zero,
    );
    expect(find.byKey(_labelKey), findsNothing);
    expect(rig.settings.showRemainingTime, isTrue);
    rig.setTimes(Duration.zero, const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_labelText(tester), '-01:00');
    report.pass('M36.5');
  });

  testWidgets('M36.6 remaining label follows the position', (tester) async {
    final rig = await _rig(tester, initial: const {_prefKey: true});
    expect(_labelText(tester), '-01:12');

    rig.setTimes(
      const Duration(minutes: 3, seconds: 30),
      const Duration(minutes: 3, seconds: 45),
    );
    await tester.pump();
    expect(_labelText(tester), '-00:15');

    rig.setTimes(
      const Duration(seconds: 5),
      const Duration(minutes: 3, seconds: 45),
    );
    await tester.pump();
    expect(_labelText(tester), '-03:40');

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(_labelText(tester), '03:45');
    rig.setTimes(
      const Duration(seconds: 50),
      const Duration(minutes: 3, seconds: 45),
    );
    await tester.pump();
    expect(_labelText(tester), '03:45');
    report.pass('M36.6');
  });

  test('M36.7 preference key is frozen and written verbatim', () async {
    expect(SettingsService.frozenPreferenceKeys, contains(_prefKey));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    var notifications = 0;
    settings.addListener(() => notifications++);

    settings.showRemainingTime = true;
    expect(prefs.getBool(_prefKey), isTrue);
    expect(notifications, 1);

    settings.showRemainingTime = true;
    expect(notifications, 1);

    settings.showRemainingTime = false;
    expect(prefs.getBool(_prefKey), isFalse);
    expect(notifications, 2);
    report.pass('M36.7');
  });

  testWidgets('M36.8 default is total duration and reading does not write', (
    tester,
  ) async {
    final rig = await _rig(tester);
    expect(rig.settings.showRemainingTime, isFalse);
    expect(rig.prefs.containsKey(_prefKey), isFalse);
    expect(_labelText(tester), '03:45');
    expect(rig.prefs.containsKey(_prefKey), isFalse);
    report.pass('M36.8');
  });

  testWidgets('M36.9 tooltip and semantics describe the current mode', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final rig = await _rig(tester);
    final l10n = _l10n(tester);
    expect(rig.settings.showRemainingTime, isFalse);

    expect(
      find.byTooltip(l10n.seekDurationToggleShowRemaining),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(_labelKey)),
      isSemantics(
        label: l10n.seekDurationToggleShowRemaining,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(_labelKey));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.seekDurationToggleShowTotal), findsOneWidget);
    expect(find.byTooltip(l10n.seekDurationToggleShowRemaining), findsNothing);
    expect(
      tester.getSemantics(find.byKey(_labelKey)),
      isSemantics(
        label: l10n.seekDurationToggleShowTotal,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    expect(
      l10n.seekDurationToggleShowTotal,
      isNot(l10n.seekDurationToggleShowRemaining),
    );
    handle.dispose();
    report.pass('M36.9');
  });
}
