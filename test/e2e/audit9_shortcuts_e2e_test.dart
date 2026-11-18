import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/l10n/app_localizations_en.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/player_shortcut_dispatcher.dart';
import 'package:dacx/screens/settings_screen.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/player_shortcuts_service.dart';
import 'package:dacx/widgets/keybinds_dialog.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

final _l10n = AppLocalizationsEn();

const _oldActionNames = [
  'openFile',
  'reopenLast',
  'playPause',
  'seekForward',
  'seekBack',
  'volumeUp',
  'volumeDown',
  'toggleMute',
  'toggleFullscreen',
  'exitFullscreen',
  'chapterNext',
  'chapterPrev',
  'screenshot',
  'cycleAudioTrack',
  'cycleSubtitleTrack',
  'toggleSubtitle',
  'toggleEqualizer',
  'playlistNext',
  'playlistPrev',
  'toggleCompactMode',
  'newWindow',
  'speedSlower',
  'speedFaster',
  'cycleSpeed',
  'openUrl',
  'cycleAdvancedLoop',
  'subtitleDelayBack',
  'subtitleDelayForward',
  'audioDelayBack',
  'audioDelayForward',
  'addPlaybackMarker',
];

const _newActions = [
  PlayerShortcutAction.toggleQueue,
  PlayerShortcutAction.stop,
  PlayerShortcutAction.openSettings,
  PlayerShortcutAction.showMediaInfo,
  PlayerShortcutAction.seekForwardLarge,
  PlayerShortcutAction.seekBackLarge,
];

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

KeyEvent _repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

PlayerShortcutAction? _resolve(
  KeyEvent event, {
  bool hasMedia = true,
  bool ctrl = false,
  bool meta = false,
  bool shift = false,
  bool alt = false,
  Map<String, List<String>>? custom,
}) {
  return PlayerShortcutsService.resolve(
    event: event,
    hasMedia: hasMedia,
    isMetaPressed: meta,
    isControlPressed: ctrl,
    isShiftPressed: shift,
    isAltPressed: alt,
    customBindings: custom,
  );
}

Future<HeadlessPlayerService> _pump(
  WidgetTester tester, {
  PlayableSource? pending,
  Map<String, Object> prefs = const {},
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices(prefs: prefs);
  final service = HeadlessPlayerService();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    PlayerScreenHarness.wrap(
      settings: services.settings,
      debugLog: services.debugLog,
      updates: services.updates,
      playerService: service,
      headlessMediaSurface: true,
      initialPendingLoad: pending,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return service;
}

Future<void> _settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool ctrl = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await _settle(tester);
}

bool _queueOpen() =>
    find.text(_l10n.dialogPlayQueueTitle).evaluate().isNotEmpty;

bool _stopEnabled(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.byIcon(Icons.stop),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder.first).onPressed != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'shortcuts',
    expectedIds: [for (var i = 1; i <= 11; i++) 'M35.$i'],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('service level', () {
    test('M35.1 every new default resolves to its action', () {
      expect(
        _resolve(_down(LogicalKeyboardKey.keyQ)),
        PlayerShortcutAction.toggleQueue,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyS), shift: true),
        PlayerShortcutAction.stop,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.comma), ctrl: true),
        PlayerShortcutAction.openSettings,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.comma), meta: true),
        PlayerShortcutAction.openSettings,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyI)),
        PlayerShortcutAction.showMediaInfo,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowRight), shift: true),
        PlayerShortcutAction.seekForwardLarge,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowLeft), shift: true),
        PlayerShortcutAction.seekBackLarge,
      );
      expect(defaultKeybinds[PlayerShortcutAction.toggleQueue], ['Q']);
      expect(defaultKeybinds[PlayerShortcutAction.stop], ['Shift+S']);
      expect(defaultKeybinds[PlayerShortcutAction.openSettings], ['Ctrl+,']);
      expect(defaultKeybinds[PlayerShortcutAction.showMediaInfo], ['I']);
      expect(defaultKeybinds[PlayerShortcutAction.seekForwardLarge], [
        'Shift+Arrow Right',
      ]);
      expect(defaultKeybinds[PlayerShortcutAction.seekBackLarge], [
        'Shift+Arrow Left',
      ]);
      expect(
        _resolve(_down(LogicalKeyboardKey.keyS), ctrl: true),
        PlayerShortcutAction.screenshot,
      );
      expect(_resolve(_down(LogicalKeyboardKey.keyS)), isNull);
      expect(_resolve(_down(LogicalKeyboardKey.keyQ), shift: true), isNull);
      expect(_resolve(_down(LogicalKeyboardKey.keyI), ctrl: true), isNull);
      report.pass('M35.1');
    });

    test('M35.2 Shift+Arrow does not trigger the plain seek', () {
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        final resolved = _resolve(_down(key), shift: true);
        expect(resolved, isNotNull);
        expect(resolved, isNot(PlayerShortcutAction.seekForward));
        expect(resolved, isNot(PlayerShortcutAction.seekBack));
      }
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowRight), ctrl: true, shift: true),
        PlayerShortcutAction.chapterNext,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowLeft), ctrl: true, shift: true),
        PlayerShortcutAction.chapterPrev,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowUp), shift: true),
        PlayerShortcutAction.volumeUp,
      );
      report.pass('M35.2');
    });

    test('M35.3 plain arrows do not trigger the large seek', () {
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowRight)),
        PlayerShortcutAction.seekForward,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowLeft)),
        PlayerShortcutAction.seekBack,
      );
      expect(
        _resolve(_repeat(LogicalKeyboardKey.arrowRight)),
        PlayerShortcutAction.seekForward,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowRight), ctrl: true),
        PlayerShortcutAction.chapterNext,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowLeft), meta: true),
        PlayerShortcutAction.chapterPrev,
      );
      report.pass('M35.3');
    });

    test('M35.4 large seek repeats and the others do not', () {
      expect(
        _resolve(_repeat(LogicalKeyboardKey.arrowRight), shift: true),
        PlayerShortcutAction.seekForwardLarge,
      );
      expect(
        _resolve(_repeat(LogicalKeyboardKey.arrowLeft), shift: true),
        PlayerShortcutAction.seekBackLarge,
      );
      expect(
        _resolve(
          _repeat(LogicalKeyboardKey.arrowRight),
          alt: true,
          custom: const {
            'seekForwardLarge': ['Alt+Arrow Right'],
          },
        ),
        PlayerShortcutAction.seekForwardLarge,
      );
      expect(
        _resolve(
          _repeat(LogicalKeyboardKey.arrowLeft),
          alt: true,
          custom: const {
            'seekBackLarge': ['Alt+Arrow Left'],
          },
        ),
        PlayerShortcutAction.seekBackLarge,
      );
      expect(_resolve(_repeat(LogicalKeyboardKey.keyQ)), isNull);
      expect(_resolve(_repeat(LogicalKeyboardKey.keyI)), isNull);
      expect(_resolve(_repeat(LogicalKeyboardKey.keyS), shift: true), isNull);
      expect(_resolve(_repeat(LogicalKeyboardKey.comma), ctrl: true), isNull);
      expect(
        _resolve(
          _repeat(LogicalKeyboardKey.keyW),
          custom: const {
            'toggleQueue': ['W'],
            'showMediaInfo': ['W'],
          },
        ),
        isNull,
      );
      report.pass('M35.4');
    });

    test('M35.5 rebinding works and suppresses the default', () {
      const rebinds = <PlayerShortcutAction, String>{
        PlayerShortcutAction.toggleQueue: 'W',
        PlayerShortcutAction.stop: 'X',
        PlayerShortcutAction.openSettings: 'Ctrl+K',
        PlayerShortcutAction.showMediaInfo: 'Y',
      };
      final keys = <String, LogicalKeyboardKey>{
        'W': LogicalKeyboardKey.keyW,
        'X': LogicalKeyboardKey.keyX,
        'Ctrl+K': LogicalKeyboardKey.keyK,
        'Y': LogicalKeyboardKey.keyY,
      };
      for (final entry in rebinds.entries) {
        final custom = {
          entry.key.name: [entry.value],
        };
        final key = keys[entry.value]!;
        final ctrl = entry.value.startsWith('Ctrl+');
        expect(
          _resolve(_down(key), ctrl: ctrl, custom: custom),
          entry.key,
          reason: 'new accelerator for ${entry.key}',
        );
        final def = defaultKeybinds[entry.key]!.single;
        final defKey = switch (entry.key) {
          PlayerShortcutAction.toggleQueue => LogicalKeyboardKey.keyQ,
          PlayerShortcutAction.stop => LogicalKeyboardKey.keyS,
          PlayerShortcutAction.openSettings => LogicalKeyboardKey.comma,
          _ => LogicalKeyboardKey.keyI,
        };
        expect(
          _resolve(
            _down(defKey),
            ctrl: def.startsWith('Ctrl+'),
            shift: def.startsWith('Shift+'),
            custom: custom,
          ),
          isNull,
          reason: 'default accelerator for ${entry.key} after rebinding',
        );
      }

      final largeCustom = {
        'seekForwardLarge': ['Alt+Arrow Right'],
        'seekBackLarge': ['Alt+Arrow Left'],
      };
      expect(
        _resolve(
          _down(LogicalKeyboardKey.arrowRight),
          alt: true,
          custom: largeCustom,
        ),
        PlayerShortcutAction.seekForwardLarge,
      );
      expect(
        _resolve(
          _down(LogicalKeyboardKey.arrowLeft),
          alt: true,
          custom: largeCustom,
        ),
        PlayerShortcutAction.seekBackLarge,
      );
      expect(
        _resolve(
          _down(LogicalKeyboardKey.arrowRight),
          shift: true,
          custom: largeCustom,
        ),
        isNull,
      );
      expect(
        _resolve(
          _down(LogicalKeyboardKey.arrowLeft),
          shift: true,
          custom: largeCustom,
        ),
        isNull,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.arrowRight), custom: largeCustom),
        PlayerShortcutAction.seekForward,
      );

      expect(
        PlayerShortcutsService.actionUsing(
          'Q',
          const {},
          except: PlayerShortcutAction.stop,
        ),
        PlayerShortcutAction.toggleQueue,
      );
      expect(
        PlayerShortcutsService.actionUsing(
          'Shift+Arrow Right',
          const {},
          except: PlayerShortcutAction.seekForward,
        ),
        PlayerShortcutAction.seekForwardLarge,
      );
      report.pass('M35.5');
    });

    testWidgets('M35.6 stored names for old actions still load', (
      tester,
    ) async {
      const values = PlayerShortcutAction.values;
      expect([
        for (final a in values.take(_oldActionNames.length)) a.name,
      ], _oldActionNames);
      expect(
        values.skip(_oldActionNames.length).toList(),
        _newActions,
        reason: 'new values must be appended after the existing ones',
      );

      final stored = {
        'seekForward': ['L'],
        'openFile': ['Ctrl+Shift+O'],
        'playPause': ['K'],
        'toggleQueue': ['W'],
      };
      final services = await PlayerScreenHarness.createServices(
        prefs: {'keybinds_v1': jsonEncode(stored)},
      );
      addTearDown(services.settings.dispose);
      final custom = services.settings.keybinds;
      expect(custom['seekForward'], ['L']);
      expect(custom['openFile'], ['Ctrl+Shift+O']);
      expect(
        _resolve(_down(LogicalKeyboardKey.keyL), custom: custom),
        PlayerShortcutAction.seekForward,
      );
      expect(
        _resolve(
          _down(LogicalKeyboardKey.keyO),
          ctrl: true,
          shift: true,
          custom: custom,
        ),
        PlayerShortcutAction.openFile,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyK), custom: custom),
        PlayerShortcutAction.playPause,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyW), custom: custom),
        PlayerShortcutAction.toggleQueue,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyI), custom: custom),
        PlayerShortcutAction.showMediaInfo,
      );
      report.pass('M35.6');
    });

    test('M35.10 no default shadows another default', () {
      for (final action in PlayerShortcutAction.values) {
        for (final accel in defaultKeybinds[action]!) {
          expect(
            PlayerShortcutsService.actionUsing(accel, const {}, except: action),
            isNull,
            reason: '"$accel" of $action is also bound to another action',
          );
        }
      }
      for (final action in _newActions) {
        expect(defaultKeybinds[action], isNotEmpty);
      }
    });

    test('M35.9 stop and media info need media in every resolver path', () {
      expect(
        _resolve(_down(LogicalKeyboardKey.keyS), shift: true, hasMedia: false),
        isNull,
      );
      expect(_resolve(_down(LogicalKeyboardKey.keyI), hasMedia: false), isNull);
      expect(
        _resolve(
          _down(LogicalKeyboardKey.keyX),
          hasMedia: false,
          custom: const {
            'stop': ['X'],
            'showMediaInfo': ['X'],
          },
        ),
        isNull,
      );
      expect(
        _resolve(
          _down(LogicalKeyboardKey.keyX),
          custom: const {
            'stop': ['X'],
          },
        ),
        PlayerShortcutAction.stop,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.keyQ), hasMedia: false),
        PlayerShortcutAction.toggleQueue,
      );
      expect(
        _resolve(_down(LogicalKeyboardKey.comma), ctrl: true, hasMedia: false),
        PlayerShortcutAction.openSettings,
      );
    });
  });

  group('keybinds dialog', () {
    testWidgets('M35.7 dialog lists the new actions with labels', (
      tester,
    ) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKeybindsDialog(
                context: context,
                settings: services.settings,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      );
      final expected = <String, String>{
        _l10n.shortcutToggleQueue: 'Q',
        _l10n.shortcutStop: 'Shift+S',
        _l10n.shortcutOpenSettings: 'Ctrl+,',
        _l10n.shortcutShowMediaInfo: 'I',
        _l10n.shortcutSeekForwardLarge: 'Shift+Arrow Right',
        _l10n.shortcutSeekBackLarge: 'Shift+Arrow Left',
      };
      expect(expected.keys.toSet().length, expected.length);
      for (final entry in expected.entries) {
        expect(entry.key.trim(), isNotEmpty);
        final title = find.text(entry.key);
        await tester.scrollUntilVisible(
          title,
          80,
          scrollable: scrollable.first,
        );
        expect(title, findsOneWidget);
        final tile = find.ancestor(of: title, matching: find.byType(ListTile));
        expect(
          find.descendant(of: tile, matching: find.text(entry.value)),
          findsOneWidget,
          reason: 'default accelerator shown for ${entry.key}',
        );
      }
      for (final action in _newActions) {
        final label = shortcutActionLabel(action, l10n: _l10n);
        expect(label.trim(), isNotEmpty);
        expect(label, isNot(action.name));
        expect(label, shortcutActionLabel(action));
      }
      report.pass('M35.7');
    });
  });

  group('real screen', () {
    testWidgets('M35.8 each shortcut does its job', (tester) async {
      final source = PlayableSource.file('/media/a.mp3');
      final player = await _pump(tester, pending: source);
      await _settle(tester);
      expect(player.openCalls.map((c) => c.path), ['/media/a.mp3']);
      expect(_stopEnabled(tester), isTrue);

      expect(_queueOpen(), isFalse);
      await _press(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(_queueOpen(), isTrue);
      await _press(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(_queueOpen(), isFalse);

      player.emitDuration(const Duration(minutes: 10));
      player.emitPosition(const Duration(minutes: 5));
      await _settle(tester);
      final seeks = <Duration>[];
      final sub = player.positionStream.listen(seeks.add);
      addTearDown(sub.cancel);

      await _press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(seeks, [const Duration(minutes: 5, seconds: 30)]);
      player.emitPosition(const Duration(minutes: 5));
      await _settle(tester);
      seeks.clear();
      await _press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(seeks, [const Duration(minutes: 4, seconds: 30)]);
      player.emitPosition(const Duration(minutes: 5));
      await _settle(tester);
      seeks.clear();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(seeks, [const Duration(minutes: 5, seconds: 5)]);
      player.emitPosition(const Duration(minutes: 5));
      await _settle(tester);
      seeks.clear();
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(seeks, [const Duration(minutes: 4, seconds: 55)]);

      player.emitPosition(const Duration(minutes: 5));
      await _settle(tester);
      seeks.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _settle(tester);
      expect(seeks.length, 2);

      expect(find.text(_l10n.dialogMediaInfoTitle), findsNothing);
      await _press(tester, LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.dialogMediaInfoTitle), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.dialogMediaInfoTitle), findsNothing);

      expect(find.byType(SettingsScreen), findsNothing);
      await _press(tester, LogicalKeyboardKey.comma, ctrl: true);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);

      expect(_stopEnabled(tester), isTrue);
      await _press(tester, LogicalKeyboardKey.keyS, shift: true);
      await tester.pumpAndSettle();
      expect(_stopEnabled(tester), isFalse);
      await tester.pump(const Duration(seconds: 2));
      report.pass('M35.8');
    });

    testWidgets('M35.9 without media only queue and settings work', (
      tester,
    ) async {
      await _pump(tester);
      await _settle(tester);
      expect(_stopEnabled(tester), isFalse);

      await _press(tester, LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text(_l10n.dialogMediaInfoTitle), findsNothing);
      await _press(tester, LogicalKeyboardKey.keyS, shift: true);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(_queueOpen(), isTrue);
      await _press(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(_queueOpen(), isFalse);

      await _press(tester, LogicalKeyboardKey.comma, ctrl: true);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      report.pass('M35.9');
    });

    testWidgets('M35.10 a focused text field keeps the new keys', (
      tester,
    ) async {
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      final actions = <PlayerShortcutAction>[];
      final dispatcher = PlayerShortcutDispatcher(
        settings: services.settings,
        isActive: () => true,
        routeIsCurrent: () => true,
        hasMedia: () => true,
        isEndDrawerOpen: () => false,
        onEscape: () => KeyEventResult.ignored,
        onShowHelp: () {},
        onAction: (action) {
          actions.add(action);
          return KeyEventResult.handled;
        },
      )..attach();
      addTearDown(dispatcher.dispose);
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(focusNode: field)),
        ),
      );
      field.requestFocus();
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await _press(tester, LogicalKeyboardKey.keyS, shift: true);
      await _press(tester, LogicalKeyboardKey.comma, ctrl: true);
      await _press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(actions, isEmpty);

      field.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      expect(actions, [PlayerShortcutAction.toggleQueue]);
      report.pass('M35.10');
    });

    testWidgets('M35.11 repeated Ctrl+, opens settings once', (tester) async {
      await _pump(tester);
      await _settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      report.pass('M35.11');
    });
  });
}
