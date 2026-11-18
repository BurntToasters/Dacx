import 'dart:async';
import 'dart:io';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/l10n/app_localizations_en.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/sleep_timer_controller.dart';
import 'package:dacx/screens/player/widgets/player_more_menu.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/playlist_service.dart';
import 'package:dacx/services/player_shortcuts_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

final _l10n = AppLocalizationsEn();

class _SlowChapterPlayer extends HeadlessPlayerService {
  Completer<void>? gate;

  @override
  Future<String?> getProperty(String name) async {
    final pending = gate;
    if (pending != null && name.startsWith('chapter-list')) {
      await pending.future;
    }
    return super.getProperty(name);
  }
}

class _OpenMenu {
  _OpenMenu({
    required this.settings,
    required this.sleep,
    required this.playlist,
    required this.chapters,
  });

  final SettingsService settings;
  final SleepTimerController sleep;
  final PlaylistService playlist;
  final ValueNotifier<bool> chapters;
  String? result;
  bool done = false;
}

Finder _items() => find.byWidgetPredicate(
  (w) => w is MenuItemButton || w is SubmenuButton,
  description: 'top level menu items',
);

Rect _menuRect(WidgetTester tester) {
  Rect? union;
  for (final element in _items().evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    union = union == null ? rect : union.expandToInclude(rect);
  }
  return union!;
}

Future<_OpenMenu> _openDirect(
  WidgetTester tester, {
  Rect? anchor,
  bool hasAudio = false,
  bool hasSub = false,
  bool chapters = false,
  bool hasFile = false,
  bool compact = false,
  ThemeData? theme,
  Map<String, Object> prefs = const {},
  Map<String, List<String>>? keybinds,
  bool activeTimer = false,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices(prefs: prefs);
  if (keybinds != null) services.settings.keybinds = keybinds;
  final sleep = SleepTimerController();
  addTearDown(sleep.dispose);
  if (activeTimer) sleep.startMinutes(30);
  final playlist = PlaylistService();
  final chapterNotifier = ValueNotifier<bool>(chapters);
  addTearDown(chapterNotifier.dispose);
  final opened = _OpenMenu(
    settings: services.settings,
    sleep: sleep,
    playlist: playlist,
    chapters: chapterNotifier,
  );
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: theme ?? ThemeData(useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  unawaited(
    showPlayerMoreMenu(
      context: hostContext,
      hasAudioOptions: hasAudio,
      hasSubOptions: hasSub,
      hasChapters: chapterNotifier,
      hasCurrentFile: () => hasFile,
      compactMode: () => compact,
      settings: services.settings,
      sleepTimer: sleep,
      playlist: playlist,
      onSetShuffle: (v) => services.settings.playlistShuffle = v,
      anchor: anchor,
    ).then((value) {
      opened.result = value;
      opened.done = true;
    }),
  );
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
  return opened;
}

Future<void> _tapItem(WidgetTester tester, String label) async {
  final item = find
      .ancestor(
        of: find.textContaining(label),
        matching: find.byWidgetPredicate(
          (w) => w is MenuItemButton || w is SubmenuButton,
        ),
      )
      .first;
  final rect = tester.getRect(item);
  await tester.tapAt(Offset(rect.left + 40, rect.center.dy));
}

Future<void> _tapPath(WidgetTester tester, List<String> path) async {
  for (final label in path) {
    await _tapItem(tester, label);
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  HeadlessPlayerService player, {
  Map<String, Object> prefs = const {},
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices(prefs: prefs);
  await tester.pumpWidget(
    PlayerScreenHarness.wrap(
      settings: services.settings,
      debugLog: services.debugLog,
      updates: services.updates,
      playerService: player,
      headlessMediaSurface: true,
      initialLoadedSource: PlayableSource.file('/test/movie.mkv'),
    ),
  );
  await tester.pump();
  await tester.pump();
}

IconButton _moreButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(of: find.byTooltip('More'), matching: find.byType(IconButton)),
);

Finder _item(String label) => find.widgetWithText(MenuItemButton, label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'menu',
    expectedIds: [for (var i = 1; i <= 13; i++) 'M21.$i'],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  testWidgets('M21.1 menu opens without waiting for the chapter refresh', (
    tester,
  ) async {
    final player = _SlowChapterPlayer();
    await _pumpScreen(tester, player);
    await player.setProperty('chapter-list/count', '2');
    await player.setProperty('chapter-list/0/title', 'One');
    await player.setProperty('chapter-list/1/title', 'Two');
    final gate = Completer<void>();
    player.gate = gate;

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump();

    expect(_item(_l10n.buttonOpenUrl), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    report.pass('M21.1');
  });

  testWidgets('M21.2 chapters appear when the refresh finishes', (
    tester,
  ) async {
    final player = _SlowChapterPlayer();
    await _pumpScreen(tester, player);
    await player.setProperty('chapter-list/count', '2');
    await player.setProperty('chapter-list/0/title', 'One');
    await player.setProperty('chapter-list/1/title', 'Two');
    final gate = Completer<void>();
    player.gate = gate;

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tracks'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tracks'), findsOneWidget);
    await _tapItem(tester, 'Tracks');
    await tester.pumpAndSettle();
    expect(find.text(_l10n.dialogChaptersTitle), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final lateGate = Completer<void>();
    final latePlayer = _SlowChapterPlayer();
    await _pumpScreen(tester, latePlayer);
    await latePlayer.setProperty('chapter-list/count', '1');
    latePlayer.gate = lateGate;
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsNothing);
    lateGate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    report.pass('M21.2');
  });

  testWidgets('M21.3 a second open request is ignored and the guard releases', (
    tester,
  ) async {
    await _pumpScreen(tester, HeadlessPlayerService());

    final button = _moreButton(tester);
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsOneWidget);

    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(PlayerScreenHarness.fullscreenCalls, [true]);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(_item(_l10n.buttonOpenUrl), findsOneWidget);
    report.pass('M21.3');
  });

  testWidgets('M21.4 menu is anchored to the given rect', (tester) async {
    const low = Rect.fromLTWH(1300, 900, 40, 40);
    await _openDirect(tester, anchor: low);
    final below = _menuRect(tester);
    expect(below.bottom, closeTo(low.top, 16));
    expect(below.right, closeTo(low.right, 16));
    expect(below.top, greaterThanOrEqualTo(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    const high = Rect.fromLTWH(900, 50, 40, 40);
    await _openDirect(tester, anchor: high);
    final above = _menuRect(tester);
    expect(above.top, closeTo(high.bottom, 16));
    expect(above.right, closeTo(high.right, 16));
    expect(above.bottom, lessThanOrEqualTo(1000));
    expect(above.topLeft, isNot(equals(below.topLeft)));
    report.pass('M21.4');
  });

  testWidgets('M21.5 menu falls back to the bottom right corner', (
    tester,
  ) async {
    await _openDirect(tester);
    final rect = _menuRect(tester);
    expect(rect.right, closeTo(1600 - 12, 16));
    expect(rect.bottom, closeTo(1000 - 64, 16));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    report.pass('M21.5');
  });

  testWidgets('M21.6 sleep timer submenu is built from the presets', (
    tester,
  ) async {
    final opened = await _openDirect(tester);
    await _tapItem(tester, _l10n.menuSleepTimer);
    await tester.pumpAndSettle();

    final labels = [
      for (final m in SleepTimerController.presetMinutes)
        _l10n.menuSleepTimerMinutes(m),
    ];
    expect(find.textContaining(' minutes'), findsNWidgets(labels.length));
    var lastDy = -1.0;
    for (final label in labels) {
      final dy = tester.getTopLeft(find.text(label)).dy;
      expect(dy, greaterThan(lastDy));
      lastDy = dy;
    }
    expect(find.text(_l10n.menuSleepTimerOff), findsNothing);

    opened.sleep.startMinutes(30);
    await tester.pump();
    expect(find.text(_l10n.menuSleepTimerOff), findsOneWidget);

    await _tapItem(tester, _l10n.menuSleepTimerMinutes(30));
    await tester.pumpAndSettle();
    opened.sleep.cancel();
    expect(opened.result, 'sleep_30');

    final menuSource = File('lib/screens/player/widgets/player_more_menu.dart')
        .readAsStringSync();
    expect(menuSource, contains('SleepTimerController.presetMinutes'));
    expect(
      RegExp(r"'sleep_\d+'").hasMatch(menuSource),
      isFalse,
      reason: 'sleep actions must not be hard-coded',
    );
    report.pass('M21.6');
  });

  testWidgets('M21.7 shortcut hints follow the user bindings', (tester) async {
    final useMac = Platform.isMacOS;
    String shown(String accelerator) =>
        PlayerShortcutsService.formatAcceleratorForDisplay(
          PlayerShortcutsService.normalizeAccelerator(accelerator),
          useMacSymbols: useMac,
        );

    await _openDirect(tester, hasFile: true);
    expect(
      find.descendant(
        of: _item(_l10n.buttonOpenUrl),
        matching: find.text(shown('Ctrl+U')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _item(_l10n.menuTakeScreenshot),
        matching: find.text(shown('Ctrl+S')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _item(_l10n.menuMiniPlayer),
        matching: find.text(shown('Ctrl+Shift+M')),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _openDirect(
      tester,
      hasFile: true,
      keybinds: {
        'openUrl': ['Ctrl+Alt+U'],
        'screenshot': <String>[],
      },
    );
    expect(
      find.descendant(
        of: _item(_l10n.buttonOpenUrl),
        matching: find.text(shown('Ctrl+Alt+U')),
      ),
      findsOneWidget,
    );
    expect(find.text(shown('Ctrl+U')), findsNothing);
    expect(
      find.descendant(
        of: _item(_l10n.menuTakeScreenshot),
        matching: find.text(shown('Ctrl+S')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _item(_l10n.menuMiniPlayer),
        matching: find.text(shown('Ctrl+Shift+M')),
      ),
      findsOneWidget,
    );
    expect(
      PlayerShortcutsService.formatAcceleratorForDisplay(
        'Ctrl+Shift+M',
        useMacSymbols: true,
      ),
      isNot('Ctrl+Shift+M'),
    );
    report.pass('M21.7');
  });

  testWidgets('M21.8 labels use the theme text styles', (tester) async {
    final source = File('lib/screens/player/widgets/player_more_menu.dart')
        .readAsStringSync();
    expect(source.contains('fontSize'), isFalse);

    await _openDirect(
      tester,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: const TextTheme(labelLarge: TextStyle(fontSize: 22)),
      ),
    );
    final style = DefaultTextStyle.of(
      tester.element(find.text(_l10n.buttonOpenUrl)),
    ).style;
    expect(style.fontSize, 22);
    report.pass('M21.8');
  });

  testWidgets('M21.9 menu is keyboard navigable', (tester) async {
    var opened = await _openDirect(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened.result, 'open_url');
    expect(_item(_l10n.buttonOpenUrl), findsNothing);

    opened = await _openDirect(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened.result, 'equalizer');

    opened = await _openDirect(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.text(
        _l10n.menuSleepTimerMinutes(SleepTimerController.presetMinutes.first),
      ),
      findsOneWidget,
    );
    expect(opened.done, isFalse);

    opened = await _openDirect(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(opened.done, isTrue);
    expect(opened.result, isNull);
    expect(_item(_l10n.buttonOpenUrl), findsNothing);
    report.pass('M21.9');
  });

  testWidgets('M21.10 every action stays reachable with its id', (
    tester,
  ) async {
    const prefs = <String, Object>{'advanced_playback_tools_enabled': true};
    final cases = <List<Object>>[
      [
        <String>[_l10n.buttonOpenUrl],
        'open_url',
      ],
      [
        <String>['Tracks', _l10n.dialogAudioTrackTitle],
        'audio',
      ],
      [
        <String>['Tracks', _l10n.dialogSubtitleTrackTitle],
        'subtitle',
      ],
      [
        <String>[_l10n.menuLoadExternalAudio],
        'external_audio',
      ],
      [
        <String>[_l10n.menuLoadExternalSubtitle],
        'external_subtitle',
      ],
      [
        <String>['Tracks', _l10n.dialogChaptersTitle],
        'chapters',
      ],
      [
        <String>[_l10n.dialogEqualizerTitle],
        'equalizer',
      ],
      [
        <String>[_l10n.menuAdvancedPlayback],
        'advanced-playback',
      ],
      [
        <String>[_l10n.menuTakeScreenshot],
        'screenshot',
      ],
      [
        <String>[_l10n.menuSleepTimer, _l10n.menuSleepTimerOff],
        'sleep_off',
      ],
      for (final m in SleepTimerController.presetMinutes)
        [
          <String>[_l10n.menuSleepTimer, _l10n.menuSleepTimerMinutes(m)],
          'sleep_$m',
        ],
      [
        <String>[_l10n.dialogKeyboardShortcutsTitle],
        'keybinds',
      ],
      [
        <String>[_l10n.menuQueueEmpty],
        'queue',
      ],
      [
        <String>[_l10n.menuAddFilesToQueue],
        'enqueue',
      ],
      [
        <String>[_l10n.menuMiniPlayer],
        'compact',
      ],
    ];
    for (final entry in cases) {
      final path = entry[0] as List<String>;
      final id = entry[1] as String;
      final opened = await _openDirect(
        tester,
        hasAudio: true,
        hasSub: true,
        chapters: true,
        hasFile: true,
        prefs: prefs,
        activeTimer: true,
      );
      if (id == 'advanced-playback') {
        expect(
          find.byKey(const ValueKey('advanced-playback-entry')),
          findsOneWidget,
        );
      }
      await _tapPath(tester, path);
      opened.sleep.cancel();
      expect(opened.result, id, reason: path.join(' > '));
      expect(_item(_l10n.buttonOpenUrl), findsNothing);
    }

    final off = await _openDirect(tester, hasFile: true);
    expect(find.byKey(const ValueKey('advanced-playback-entry')), findsNothing);
    expect(find.text('Tracks'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(off.done, isTrue);
    report.pass('M21.10');
  });

  test('M21.11 dispatch maps each action id to one callback', () {
    final calls = <String>[];
    final actions = PlayerMoreMenuActions(
      onOpenUrl: () => calls.add('open_url'),
      onAudioTracks: () => calls.add('audio'),
      onSubtitleTracks: () => calls.add('subtitle'),
      onExternalAudio: () => calls.add('external_audio'),
      onExternalSubtitle: () => calls.add('external_subtitle'),
      onChapters: () => calls.add('chapters'),
      onEqualizer: () => calls.add('equalizer'),
      onAdvancedPlayback: () => calls.add('advanced-playback'),
      onScreenshot: () => calls.add('screenshot'),
      onSleepTimer: (m) => calls.add('sleep:$m'),
      onKeybinds: () => calls.add('keybinds'),
      onQueue: () => calls.add('queue'),
      onEnqueue: () => calls.add('enqueue'),
      onSetShuffle: (v) => calls.add('shuffle:$v'),
      onCompact: () => calls.add('compact'),
    );
    const ids = [
      'open_url',
      'audio',
      'subtitle',
      'external_audio',
      'external_subtitle',
      'chapters',
      'equalizer',
      'advanced-playback',
      'screenshot',
      'keybinds',
      'queue',
      'enqueue',
      'compact',
    ];
    for (final id in ids) {
      calls.clear();
      dispatchPlayerMoreMenuResult(id, actions);
      expect(calls, [id], reason: id);
    }
    calls.clear();
    dispatchPlayerMoreMenuResult('sleep_off', actions);
    expect(calls, ['sleep:null']);
    for (final m in SleepTimerController.presetMinutes) {
      calls.clear();
      dispatchPlayerMoreMenuResult('sleep_$m', actions);
      expect(calls, ['sleep:$m']);
    }
    calls.clear();
    dispatchPlayerMoreMenuResult('sleep_7', actions);
    dispatchPlayerMoreMenuResult('nope', actions);
    dispatchPlayerMoreMenuResult(null, actions);
    expect(calls, isEmpty);
    report.pass('M21.11');
  });

  testWidgets('M21.12 shuffle keeps the menu open and mini-player closes it', (
    tester,
  ) async {
    final opened = await _openDirect(tester);
    expect(opened.settings.playlistShuffle, isFalse);
    await _tapItem(tester, _l10n.menuShuffleQueue);
    await tester.pumpAndSettle();
    expect(opened.settings.playlistShuffle, isTrue);
    expect(opened.done, isFalse);
    expect(_item(_l10n.buttonOpenUrl), findsOneWidget);
    final toggle = tester.widget<Switch>(
      find.descendant(
        of: _item(_l10n.menuShuffleQueue),
        matching: find.byType(Switch),
      ),
    );
    expect(toggle.value, isTrue);

    await _tapItem(tester, _l10n.menuMiniPlayer);
    await tester.pumpAndSettle();
    expect(opened.done, isTrue);
    expect(opened.result, 'compact');
    report.pass('M21.12');
  });

  testWidgets('M21.13 keyboard shortcuts dialog opens from the menu', (
    tester,
  ) async {
    await _pumpScreen(tester, HeadlessPlayerService());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await _tapItem(tester, _l10n.dialogKeyboardShortcutsTitle);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    report.pass('M21.13');
  });
}
