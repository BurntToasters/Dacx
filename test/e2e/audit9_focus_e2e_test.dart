import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/player_settings_route.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:dacx/widgets/transport_controls.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

const _titleOverlay = ValueKey('fullscreen-title-overlay');
const _dockOverlay = ValueKey('fullscreen-dock-overlay');
const _fullscreenOpacity = ValueKey('chrome-overlay-opacity');
const _miniOverlay = Key('mini-player-overlay-ignore');
const _miniOpacity = Key('mini-player-overlay-opacity');
const _miniLayout = ValueKey('mini-player-layout');
const _coverText = 'focus cover dialog';
final _song = PlayableSource.file('/media/song.mp3');

Future<HeadlessPlayerService> _pumpPlayer(WidgetTester tester) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  final player = HeadlessPlayerService();
  await tester.pumpWidget(
    PlayerScreenHarness.wrap(
      settings: services.settings,
      debugLog: services.debugLog,
      updates: services.updates,
      playerService: player,
      headlessMediaSurface: true,
      initialLoadedSource: _song,
    ),
  );
  await tester.pump();
  await tester.pump();
  return player;
}

Future<HeadlessPlayerService> _pumpMini(WidgetTester tester) async {
  final player = await _pumpPlayer(tester);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await _elapse(tester, const Duration(milliseconds: 400));
  expect(find.byKey(_miniLayout), findsOneWidget);
  return player;
}

Future<void> _enterFullscreen(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(PlayerScreenHarness.fullscreenCalls.last, isTrue);
}

Future<void> _elapse(WidgetTester tester, Duration duration) =>
    tester.pump(duration);

bool _fullscreenShown(WidgetTester tester, ValueKey<String> overlay) {
  final opacity = find.descendant(
    of: find.byKey(overlay),
    matching: find.byKey(_fullscreenOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity).opacity > 0.5;
}

bool _miniShown(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_miniOpacity)).opacity > 0.5;

bool _focusWithin(Key key) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = false;
  context.visitAncestorElements((element) {
    found = element.widget.key == key;
    return !found;
  });
  return found;
}

Future<bool> _traverseUntil(
  WidgetTester tester,
  bool Function() reached, {
  int steps = 60,
}) async {
  for (var i = 0; i < steps; i++) {
    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pump();
    if (reached()) return true;
  }
  return false;
}

void _requestSettings(WidgetTester tester) {
  tester
      .widget<TransportControls>(find.byType(TransportControls))
      .onSettingsPressed();
}

void _noLog(
  String event, {
  DebugLogCategory? category,
  String? message,
  Map<String, Object?>? details,
  String? Function()? messageBuilder,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity? severity,
}) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'focus',
    expectedIds: [
      for (var i = 1; i <= 7; i++) 'M42.$i',
      for (var i = 1; i <= 4; i++) 'M43.$i',
    ],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 42: hidden overlays leave the focus order', () {
    testWidgets('M42.1 hidden fullscreen controls cannot take focus', (
      tester,
    ) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);
      await _elapse(tester, const Duration(seconds: 4));
      expect(_fullscreenShown(tester, _dockOverlay), isFalse);

      final reached = await _traverseUntil(
        tester,
        () => _focusWithin(_titleOverlay) || _focusWithin(_dockOverlay),
      );
      expect(reached, isFalse);
      report.pass('M42.1');
    });

    testWidgets('M42.2 hidden mini-player controls cannot take focus', (
      tester,
    ) async {
      await _pumpMini(tester);
      await _elapse(tester, const Duration(milliseconds: 2500));
      await _elapse(tester, const Duration(milliseconds: 300));
      expect(_miniShown(tester), isFalse);

      final reached = await _traverseUntil(
        tester,
        () => _focusWithin(_miniOverlay),
      );
      expect(reached, isFalse);
      report.pass('M42.2');
    });

    testWidgets('M42.3 Tab reveals hidden fullscreen controls', (tester) async {
      final player = await _pumpPlayer(tester);
      player.emitPlaying(true);
      await tester.pump();
      await _enterFullscreen(tester);
      await _elapse(tester, const Duration(seconds: 4));
      expect(_fullscreenShown(tester, _dockOverlay), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _elapse(tester, const Duration(milliseconds: 300));
      expect(_fullscreenShown(tester, _titleOverlay), isTrue);
      expect(_fullscreenShown(tester, _dockOverlay), isTrue);
      report.pass('M42.3');
    });

    testWidgets('M42.4 Tab reveals a hidden mini-player overlay', (
      tester,
    ) async {
      await _pumpMini(tester);
      await _elapse(tester, const Duration(milliseconds: 2500));
      await _elapse(tester, const Duration(milliseconds: 300));
      expect(_miniShown(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _elapse(tester, const Duration(milliseconds: 300));
      expect(_miniShown(tester), isTrue);
      report.pass('M42.4');
    });

    testWidgets('M42.5 Tab still moves focus to the next control', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      await _enterFullscreen(tester);
      final before = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final after = FocusManager.instance.primaryFocus;
      expect(after, isNotNull);
      expect(identical(after, before), isFalse);
      report.pass('M42.5');
    });

    testWidgets(
      'M42.6 Space reaches the player after fullscreen controls hide',
      (tester) async {
        final player = await _pumpPlayer(tester);
        player.emitPlaying(true);
        await tester.pump();
        await _enterFullscreen(tester);
        final reached = await _traverseUntil(
          tester,
          () => _focusWithin(_dockOverlay),
        );
        expect(reached, isTrue);

        await _elapse(tester, const Duration(seconds: 4));
        expect(_fullscreenShown(tester, _dockOverlay), isFalse);
        expect(_focusWithin(_dockOverlay), isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(player.playPauseInvocations, 1);
        report.pass('M42.6');
      },
    );

    testWidgets(
      'M42.6 Space reaches the player after mini-player controls hide',
      (tester) async {
        final player = await _pumpMini(tester);
        player.emitPlaying(true);
        await tester.pump();
        final reached = await _traverseUntil(
          tester,
          () => _focusWithin(_miniOverlay),
        );
        expect(reached, isTrue);

        await _elapse(tester, const Duration(milliseconds: 2500));
        await _elapse(tester, const Duration(milliseconds: 300));
        expect(_miniShown(tester), isFalse);
        expect(_focusWithin(_miniOverlay), isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(player.playPauseInvocations, 1);
        report.pass('M42.6');
      },
    );

    testWidgets('M42.7 visible fullscreen controls take focus', (tester) async {
      await _pumpPlayer(tester);
      await _enterFullscreen(tester);
      expect(_fullscreenShown(tester, _dockOverlay), isTrue);

      final reached = await _traverseUntil(
        tester,
        () => _focusWithin(_titleOverlay) || _focusWithin(_dockOverlay),
      );
      expect(reached, isTrue);
      report.pass('M42.7');
    });

    testWidgets('M42.7 visible mini-player controls take focus', (
      tester,
    ) async {
      await _pumpMini(tester);
      expect(_miniShown(tester), isTrue);

      final reached = await _traverseUntil(
        tester,
        () => _focusWithin(_miniOverlay),
      );
      expect(reached, isTrue);
      report.pass('M42.7');
    });
  });

  group('Finding 43: Settings opens over a dialog', () {
    testWidgets('M43.1 Settings opens while a dialog covers the player', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(PlayerScreen)),
          builder: (_) => const AlertDialog(content: Text(_coverText)),
        ),
      );
      await _elapse(tester, const Duration(milliseconds: 400));
      expect(find.text(_coverText), findsOneWidget);

      _requestSettings(tester);
      await _elapse(tester, const Duration(milliseconds: 400));
      expect(find.byType(SettingsScreen), findsOneWidget);
      report.pass('M43.1');
    });

    testWidgets('M43.2 two requests in one frame open one Settings route', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      _requestSettings(tester);
      _requestSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      report.pass('M43.2');
    });

    testWidgets('M43.3 Settings opens again after it is closed', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      _requestSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);

      _requestSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      report.pass('M43.3');
    });

    testWidgets(
      'M43.4 the Settings future completes when the route is popped',
      (tester) async {
        PlayerScreenHarness.configureDesktopViewport(tester);
        final services = await PlayerScreenHarness.createServices();
        late BuildContext appContext;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
              useMaterial3: true,
              extensions: [
                WindowVisuals.fromScheme(
                  ColorScheme.fromSeed(seedColor: Colors.blueGrey),
                  blurEnabled: false,
                  blurStrength: 0,
                ),
              ],
            ),
            home: Builder(
              builder: (context) {
                appContext = context;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pump();

        final opened = openPlayerSettings(
          context: appContext,
          settings: services.settings,
          debugLog: services.debugLog,
          updateService: services.updates,
          log: _noLog,
        );
        var completed = false;
        unawaited(
          opened.whenComplete(() {
            completed = true;
          }),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);

        Navigator.of(appContext).pop();
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        report.pass('M43.4');
      },
    );
  });
}
