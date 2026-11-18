import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/l10n/app_localizations_en.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/player_remote.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/tray_service.dart';
import 'package:dacx/theme/window_visuals.dart';

import '../support/audit9_report.dart';
import '../support/player_screen_harness.dart';

final _l10n = AppLocalizationsEn();
final _labels = TrayLabels.fromL10n(_l10n);

class _Player extends HeadlessPlayerService {
  final Map<String, Map<String, String>> tags = {};

  @override
  Future<String?> getProperty(String name) async {
    const prefix = 'metadata/by-key/';
    if (!name.startsWith(prefix)) return super.getProperty(name);
    final path = await super.getProperty('path');
    return tags[path]?[name.substring(prefix.length)];
  }
}

typedef _Rig = ({
  _Player player,
  SettingsService settings,
  PlayerRemote remote,
  TrayService tray,
  List<int> quits,
});

Future<_Rig> _pump(
  WidgetTester tester, {
  PlayableSource? source,
  List<PlayableSource>? playlist,
  PlayableSource? pending,
  LoopMode? loop,
  _Player? player,
  PlayerRemote? remote,
}) async {
  PlayerScreenHarness.configureDesktopViewport(tester);
  final services = await PlayerScreenHarness.createServices();
  if (loop != null) services.settings.loopMode = loop;
  final service = player ?? _Player();
  final bridge = remote ?? PlayerRemote();
  final quits = <int>[];
  final tray = TrayService(
    onQuit: () async {
      quits.add(1);
    },
    remote: bridge,
  );
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
        playerService: service,
        headlessMediaSurface: true,
        initialLoadedSource: source,
        initialPlaylistSources: playlist,
        initialPendingLoad: pending,
        playerRemote: bridge,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _settle(tester);
  return (
    player: service,
    settings: services.settings,
    remote: bridge,
    tray: tray,
    quits: quits,
  );
}

Future<void> _settle(WidgetTester tester, {int steps = 8}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

TrayMenuSpec _spec(PlayerRemote remote, {int limit = 127}) =>
    TrayMenuSpec.build(remote.value, _labels, tooltipLimit: limit);

TrayMenuEntry _entry(TrayMenuSpec spec, TrayAction action) =>
    spec.entries.firstWhere((e) => e.action == action);

bool _enabled(TrayMenuSpec spec, TrayAction action) =>
    _entry(spec, action).enabled;

NowPlayingState _state({
  String? title,
  String? artist,
  bool isPlaying = false,
  bool hasMedia = true,
  bool canGoNext = false,
  bool canGoPrevious = false,
}) => NowPlayingState(
  title: title,
  artist: artist,
  isPlaying: isPlaying,
  hasMedia: hasMedia,
  canGoNext: canGoNext,
  canGoPrevious: canGoPrevious,
);

TrayMenuSpec _specOf(NowPlayingState state, {int limit = 127}) =>
    TrayMenuSpec.build(state, _labels, tooltipLimit: limit);

bool _hasLoneSurrogate(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final high = unit >= 0xD800 && unit <= 0xDBFF;
    final low = unit >= 0xDC00 && unit <= 0xDFFF;
    if (high) {
      if (i + 1 >= units.length) return true;
      final next = units[i + 1];
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (low) {
      return true;
    }
  }
  return false;
}

final _a = PlayableSource.file('/media/a.mp3');
final _b = PlayableSource.file('/media/b.mp3');
final _c = PlayableSource.file('/media/c.mp3');
final _clip = PlayableSource.file('/media/clip.mp4');
final _song = PlayableSource.file('/media/song.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'tray',
    expectedIds: [for (var i = 1; i <= 15; i++) 'M27.$i'],
  );

  setUp(PlayerScreenHarness.installChannelMocks);
  tearDown(PlayerScreenHarness.uninstallChannelMocks);
  tearDownAll(report.write);

  group('Finding 27: tray controls', () {
    testWidgets('M27.1 no media disables transport and shows plain Dacx', (
      tester,
    ) async {
      final rig = await _pump(tester);
      final spec = _spec(rig.remote);
      expect(rig.remote.value, NowPlayingState.idle);
      expect(_enabled(spec, TrayAction.playPause), isFalse);
      expect(_enabled(spec, TrayAction.next), isFalse);
      expect(_enabled(spec, TrayAction.previous), isFalse);
      expect(_enabled(spec, TrayAction.show), isTrue);
      expect(_enabled(spec, TrayAction.quit), isTrue);
      expect(_entry(spec, TrayAction.playPause).label, _l10n.actionPlay);
      expect(spec.tooltip, 'Dacx');
      report.pass('M27.1');
    });

    testWidgets('M27.2 playing reads Pause with transport enabled', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      await rig.remote.next();
      await _settle(tester);
      rig.player.emitPlaying(true);
      await _settle(tester);
      final spec = _spec(rig.remote);
      expect(rig.remote.value.isPlaying, isTrue);
      expect(_entry(spec, TrayAction.playPause).label, _l10n.actionPause);
      expect(_enabled(spec, TrayAction.playPause), isTrue);
      expect(_enabled(spec, TrayAction.next), isTrue);
      expect(_enabled(spec, TrayAction.previous), isTrue);
      report.pass('M27.2');
    });

    testWidgets('M27.3 paused flips the label back to Play', (tester) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      await rig.remote.next();
      await _settle(tester);
      rig.player.emitPlaying(true);
      await _settle(tester);
      final playing = _spec(rig.remote);
      rig.player.emitPlaying(false);
      await _settle(tester);
      final paused = _spec(rig.remote);
      expect(_entry(paused, TrayAction.playPause).label, _l10n.actionPlay);
      expect(_enabled(paused, TrayAction.playPause), isTrue);
      expect(paused, isNot(playing));
      report.pass('M27.3');
    });

    testWidgets('M27.4 a single item with loop off has no next or previous', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _clip);
      final spec = _spec(rig.remote);
      expect(_enabled(spec, TrayAction.playPause), isTrue);
      expect(_enabled(spec, TrayAction.next), isFalse);
      expect(_enabled(spec, TrayAction.previous), isFalse);
      report.pass('M27.4');
    });

    testWidgets('M27.5 ends of the queue follow the loop policy', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      var spec = _spec(rig.remote);
      expect(_enabled(spec, TrayAction.next), isTrue);
      expect(_enabled(spec, TrayAction.previous), isFalse);

      await rig.remote.next();
      await _settle(tester);
      await rig.remote.next();
      await _settle(tester);
      spec = _spec(rig.remote);
      expect(_enabled(spec, TrayAction.next), isFalse);
      expect(_enabled(spec, TrayAction.previous), isTrue);

      rig.settings.loopMode = LoopMode.loop;
      await _settle(tester);
      spec = _spec(rig.remote);
      expect(_enabled(spec, TrayAction.next), isTrue);
      expect(_enabled(spec, TrayAction.previous), isTrue);
      report.pass('M27.5');
    });

    test('M27.6 menu order and labels come from localization', () {
      final spec = _specOf(
        _state(title: 'T', isPlaying: true, canGoNext: true),
      );
      expect(spec.entries.map((e) => e.action).toList(), [
        TrayAction.playPause,
        TrayAction.next,
        TrayAction.previous,
        null,
        TrayAction.show,
        TrayAction.quit,
      ]);
      expect(spec.entries[3].isSeparator, isTrue);
      expect(_entry(spec, TrayAction.playPause).label, _l10n.actionPause);
      expect(_entry(spec, TrayAction.next).label, _l10n.trayNext);
      expect(_entry(spec, TrayAction.previous).label, _l10n.trayPrevious);
      expect(_entry(spec, TrayAction.show).label, _l10n.trayShow);
      expect(_entry(spec, TrayAction.quit).label, _l10n.trayQuit);
      final idle = _specOf(NowPlayingState.idle);
      expect(_entry(idle, TrayAction.playPause).label, _l10n.actionPlay);
      report.pass('M27.6');
    });

    test('M27.7 tooltip names the track and artist without em dashes', () {
      expect(_specOf(NowPlayingState.idle).tooltip, 'Dacx');
      final titled = _specOf(_state(title: 'Song Title')).tooltip;
      expect(titled, _l10n.trayTooltipTrack('Song Title'));
      expect(titled, contains('Song Title'));
      expect(titled, endsWith('Dacx'));

      final withArtist = _specOf(
        _state(title: 'Song Title', artist: 'The Artist'),
      ).tooltip;
      expect(
        withArtist,
        _l10n.trayTooltipTrackArtist('Song Title', 'The Artist'),
      );
      expect(withArtist, contains('Song Title'));
      expect(withArtist, contains('The Artist'));
      expect(withArtist, endsWith('Dacx'));

      for (final text in [titled, withArtist]) {
        expect(text.contains('—'), isFalse);
        expect(text.contains('–'), isFalse);
      }
      expect(_l10n.trayTooltipTrack('x').contains('—'), isFalse);
      expect(_l10n.trayTooltipTrackArtist('x', 'y').contains('—'), isFalse);

      final blankArtist = _specOf(_state(title: 'Song Title', artist: '   '))
          .tooltip;
      expect(blankArtist, titled);
      final noTitle = _specOf(_state(title: '  ')).tooltip;
      expect(noTitle, 'Dacx');
      report.pass('M27.7');
    });

    test('M27.8 tooltip is truncated to the platform limit', () {
      final longTitle = 'T' * 400;
      final longArtist = 'A' * 400;
      final cases = <NowPlayingState>[
        _state(title: longTitle),
        _state(title: 'Short', artist: longArtist),
        _state(title: longTitle, artist: longArtist),
        _state(title: '\u{1F3B5}' * 200, artist: '\u{1F3A4}' * 200),
        _state(title: '\u{1F3B5}' * 200),
      ];
      for (final state in cases) {
        final tip = _specOf(state).tooltip;
        expect(tip.length, lessThanOrEqualTo(127), reason: state.title);
        expect(tip, endsWith('Dacx'));
        expect(tip, contains('…'));
        expect(_hasLoneSurrogate(tip), isFalse);
      }
      final exact = 'x' * (127 - _l10n.trayTooltipTrack('').length);
      final fits = _specOf(_state(title: exact)).tooltip;
      expect(fits.length, 127);
      expect(fits.contains('…'), isFalse);

      for (final limit in [1, 5, 10, 20]) {
        final tip = _specOf(
          _state(title: longTitle, artist: longArtist),
          limit: limit,
        ).tooltip;
        expect(tip.length, lessThanOrEqualTo(limit));
        expect(_hasLoneSurrogate(tip), isFalse);
      }
      report.pass('M27.8');
    });

    test('M27.9 specs are equal exactly when the visible state is equal', () {
      final base = _state(
        title: 'T',
        artist: 'A',
        isPlaying: true,
        canGoNext: true,
        canGoPrevious: true,
      );
      expect(_specOf(base), _specOf(base));
      expect(_specOf(base).hashCode, _specOf(base).hashCode);
      final variants = <NowPlayingState>[
        _state(
          title: 'T',
          artist: 'A',
          isPlaying: false,
          canGoNext: true,
          canGoPrevious: true,
        ),
        _state(
          title: 'T2',
          artist: 'A',
          isPlaying: true,
          canGoNext: true,
          canGoPrevious: true,
        ),
        _state(
          title: 'T',
          artist: 'B',
          isPlaying: true,
          canGoNext: true,
          canGoPrevious: true,
        ),
        _state(
          title: 'T',
          artist: 'A',
          isPlaying: true,
          canGoNext: false,
          canGoPrevious: true,
        ),
        _state(
          title: 'T',
          artist: 'A',
          isPlaying: true,
          canGoNext: true,
          canGoPrevious: false,
        ),
        _state(
          title: 'T',
          artist: 'A',
          isPlaying: true,
          hasMedia: false,
          canGoNext: true,
          canGoPrevious: true,
        ),
      ];
      for (final variant in variants) {
        expect(_specOf(variant), isNot(_specOf(base)));
      }
      report.pass('M27.9');
    });

    testWidgets('M27.10 tray commands reach the real screen', (tester) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b, _c]);
      await rig.tray.activate(TrayAction.playPause);
      await _settle(tester);
      expect(rig.player.playPauseInvocations, 1);

      await rig.tray.activate(TrayAction.next);
      await _settle(tester);
      expect(rig.player.openCalls.last.path, _b.value);

      await rig.tray.activate(TrayAction.previous);
      await _settle(tester);
      expect(rig.player.openCalls.last.path, _a.value);

      final detached = PlayerRemote();
      final lone = TrayService(onQuit: () async {}, remote: detached);
      await lone.activate(TrayAction.playPause);
      await lone.activate(TrayAction.next);
      await lone.activate(TrayAction.previous);
      final bare = TrayService(onQuit: () async {});
      await bare.activate(TrayAction.next);
      report.pass('M27.10');
    });

    testWidgets('M27.11 the screen publishes now-playing state', (
      tester,
    ) async {
      final player = _Player()
        ..tags[_song.value] = {'title': 'Song Title', 'artist': 'The Artist'}
        ..tags[_b.value] = {'title': 'B Title'};
      final rig = await _pump(tester, pending: _song, player: player);
      expect(rig.remote.value.hasMedia, isTrue);
      expect(rig.remote.value.title, 'Song Title');
      expect(rig.remote.value.artist, 'The Artist');
      expect(rig.remote.value.canGoNext, isFalse);
      expect(rig.remote.value.canGoPrevious, isFalse);
      expect(rig.remote.value.isPlaying, isTrue);
      expect(
        _spec(rig.remote).tooltip,
        _l10n.trayTooltipTrackArtist('Song Title', 'The Artist'),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      final second = await _pump(
        tester,
        source: _a,
        playlist: [_a, _b],
        player: _Player()..tags.addAll(player.tags),
      );
      expect(second.remote.value.hasMedia, isTrue);
      expect(second.remote.value.canGoNext, isTrue);
      expect(second.remote.value.canGoPrevious, isFalse);
      final firstTitle = second.remote.value.title;
      second.player.emitPlaying(true);
      await _settle(tester);
      expect(second.remote.value.isPlaying, isTrue);
      second.player.emitPlaying(false);
      await _settle(tester);
      expect(second.remote.value.isPlaying, isFalse);

      await second.remote.next();
      await _settle(tester);
      expect(second.remote.value.title, 'B Title');
      expect(second.remote.value.title, isNot(firstTitle));
      expect(second.remote.value.canGoNext, isFalse);
      expect(second.remote.value.canGoPrevious, isTrue);

      second.settings.loopMode = LoopMode.loop;
      await _settle(tester);
      expect(second.remote.value.canGoNext, isTrue);
      report.pass('M27.11');
    });

    testWidgets('M27.12 the screen unregisters on dispose', (tester) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b]);
      expect(rig.remote.isAttached, isTrue);
      expect(rig.remote.value.hasMedia, isTrue);
      await rig.remote.playPause();
      await _settle(tester);
      expect(rig.player.playPauseInvocations, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expect(rig.remote.isAttached, isFalse);
      expect(rig.remote.value, NowPlayingState.idle);
      await rig.remote.playPause();
      await rig.remote.next();
      await rig.remote.previous();
      expect(rig.player.playPauseInvocations, 1);
      expect(rig.player.openCalls, isEmpty);

      final remote = PlayerRemote();
      final calls = <String>[];
      PlayerRemoteCommands commands(String name) => PlayerRemoteCommands(
        playPause: () async => calls.add('$name:pp'),
        next: () async => calls.add('$name:next'),
        previous: () async => calls.add('$name:prev'),
      );
      final older = commands('old');
      final newer = commands('new');
      remote.attach(older);
      remote.attach(newer);
      remote.detach(older);
      expect(remote.isAttached, isTrue);
      await remote.next();
      expect(calls, ['new:next']);
      remote.detach(newer);
      await remote.next();
      expect(calls, ['new:next']);
      remote.dispose();
      remote.update(_state(title: 'late'));
      remote.detach(newer);
      await remote.playPause();
      expect(calls, ['new:next']);
      report.pass('M27.12');
    });

    testWidgets('M27.13 position ticks and unchanged state never notify', (
      tester,
    ) async {
      final rig = await _pump(tester, source: _a, playlist: [_a, _b]);
      rig.player.emitPlaying(true);
      rig.player.emitDuration(const Duration(minutes: 3));
      await _settle(tester);
      var notified = 0;
      rig.remote.addListener(() => notified++);
      for (var i = 1; i <= 40; i++) {
        rig.player.emitPosition(Duration(milliseconds: i * 250));
        await tester.pump(const Duration(milliseconds: 250));
      }
      rig.player.emitDuration(const Duration(minutes: 3));
      await _settle(tester);
      expect(notified, 0);

      rig.remote.update(rig.remote.value);
      rig.remote.update(
        _state(
          title: rig.remote.value.title,
          artist: rig.remote.value.artist,
          isPlaying: rig.remote.value.isPlaying,
          hasMedia: rig.remote.value.hasMedia,
          canGoNext: rig.remote.value.canGoNext,
          canGoPrevious: rig.remote.value.canGoPrevious,
        ),
      );
      expect(notified, 0);

      rig.player.emitPlaying(false);
      await _settle(tester);
      expect(notified, 1);
      report.pass('M27.13');
    });

    testWidgets(
      'M27.14 Windows left click shows the window, right opens menu',
      (tester) async {
        expect(
          TrayService.clickAction(TrayClick.click, isLinux: false),
          TrayClickAction.showWindow,
        );
        expect(
          TrayService.clickAction(TrayClick.rightClick, isLinux: false),
          TrayClickAction.openMenu,
        );
        expect(
          TrayService.clickAction(TrayClick.click, isLinux: false),
          TrayClickAction.showWindow,
        );
        expect(
          TrayService.clickAction(TrayClick.rightClick, isLinux: false),
          TrayClickAction.openMenu,
        );
        expect(
          TrayService.clickAction(TrayClick.click, isLinux: true),
          TrayClickAction.none,
        );
        expect(
          TrayService.clickAction(TrayClick.rightClick, isLinux: true),
          TrayClickAction.none,
        );

        final tray = TrayService(onQuit: () async {});
        var menuOpens = 0;
        PlayerScreenHarness.windowManagerCalls.clear();
        await tray.handleClick(
          TrayClick.click,
          openMenu: () => menuOpens++,
          isLinux: false,
        );
        final methods = PlayerScreenHarness.windowManagerCalls
            .map((c) => c.method)
            .toList();
        expect(methods, containsAllInOrder(['show', 'focus']));
        expect(menuOpens, 0);

        PlayerScreenHarness.windowManagerCalls.clear();
        await tray.handleClick(
          TrayClick.rightClick,
          openMenu: () => menuOpens++,
          isLinux: false,
        );
        expect(menuOpens, 1);
        expect(
          PlayerScreenHarness.windowManagerCalls.map((c) => c.method),
          isNot(contains('show')),
        );

        PlayerScreenHarness.windowManagerCalls.clear();
        await tray.handleClick(
          TrayClick.click,
          openMenu: () => menuOpens++,
          isLinux: true,
        );
        expect(menuOpens, 1);
        expect(PlayerScreenHarness.windowManagerCalls, isEmpty);
        report.pass('M27.14');
      },
    );

    testWidgets('M27.15 Show and Quit keep their behavior', (tester) async {
      final rig = await _pump(tester, source: _a);
      PlayerScreenHarness.windowManagerCalls.clear();
      await rig.tray.activate(TrayAction.show);
      final methods = PlayerScreenHarness.windowManagerCalls
          .map((c) => c.method)
          .toList();
      expect(methods, containsAllInOrder(['show', 'focus']));
      expect(rig.quits, isEmpty);
      await rig.tray.activate(TrayAction.quit);
      expect(rig.quits, hasLength(1));
      report.pass('M27.15');
    });
  });

  test('tray stays disabled under FLUTTER_TEST', () async {
    final tray = TrayService(onQuit: () async {});
    await tray.init(labels: _labels);
    expect(tray.isInitialized, isFalse);
    await tray.dispose();
  });
}
