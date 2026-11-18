import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player/widgets/audio_now_playing_view.dart';
import 'package:dacx/screens/player/widgets/player_empty_state.dart';

import '../support/audit9_report.dart';

final report = Audit9Report(
  'audio-empty',
  expectedIds: [
    'M20.1',
    'M20.2',
    'M20.3',
    'M20.4',
    'M20.5',
    'M20.6',
    'M20.7',
    'M22.1',
    'M22.2',
    'M22.3',
    'M22.4',
    'M22.5',
    'M22.6',
    'M22.7',
    'M22.8',
    'M22.9',
  ],
);

const _stacked = Key('audio-layout-stacked');
const _side = Key('audio-layout-side');
const _text = Key('audio-layout-text');
const _art = Key('audio-album-art');
const _iconArt = Key('audio-icon-art');
const _caption = Key('audio-caption');
const _title = Key('audio-title');
const _artist = Key('audio-artist');

const _longText =
    'An extremely long track title that keeps going and going and going '
    'well past any reasonable width so that wrapping and ellipsis both '
    'have to work at tiny sizes';

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget body) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
    useMaterial3: true,
  ),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

Widget _audio({
  bool art = false,
  String? title = 'Song Title',
  String? artist = 'The Artist',
  String? album,
}) {
  return AudioNowPlayingView(
    showAlbumArt: art,
    source: PlayableSource.file('/music/some-file.mp3'),
    mediaDisplayTitle: title,
    mediaDisplayArtist: artist,
    videoController: null,
    album: album,
  );
}

Future<void> _pumpAudio(WidgetTester tester, Size size, Widget view) async {
  _setWindow(tester, size);
  await tester.pumpWidget(_app(view));
  await tester.pumpAndSettle();
}

Widget _empty({
  bool tipDismissed = false,
  List<String> recent = const [],
  List<String>? log,
}) {
  void mark(String name) => log?.add(name);
  return PlayerEmptyState(
    tipDismissed: tipDismissed,
    onDismissTip: () => mark('dismiss'),
    onOpenFile: () => mark('file'),
    onOpenFolder: () => mark('folder'),
    onOpenPlaylist: () => mark('playlist'),
    onOpenUrl: () => mark('url'),
    onReopenLast: () => mark('reopen'),
    recentFiles: recent,
    onOpenRecent: (path) => mark('recent:$path'),
  );
}

Future<void> _pumpEmpty(WidgetTester tester, Size size, Widget view) async {
  _setWindow(tester, size);
  await tester.pumpWidget(_app(view));
  await tester.pumpAndSettle();
}

List<String> _recents(int count) => [
  for (var i = 0; i < count; i++) '/music/album$i/track$i.mp3',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(report.write);

  group('Finding 20: audio view', () {
    testWidgets('M20.1 never overflows at any size', (tester) async {
      const sizes = [
        Size(1280, 720),
        Size(800, 600),
        Size(480, 320),
        Size(480, 190),
        Size(300, 150),
        Size(200, 120),
      ];
      for (final size in sizes) {
        for (final art in [true, false]) {
          for (final long in [true, false]) {
            await _pumpAudio(
              tester,
              size,
              _audio(
                art: art,
                title: long ? _longText : 'Short',
                artist: long ? _longText : null,
                album: long ? _longText : null,
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size art=$art long=$long',
            );
          }
        }
      }
      report.pass('M20.1');
    });

    testWidgets('M20.2 layout adapts to height', (tester) async {
      await _pumpAudio(tester, const Size(1280, 720), _audio(art: true));
      expect(find.byKey(_stacked), findsOneWidget);
      expect(find.byKey(_side), findsNothing);
      expect(find.byKey(_text), findsNothing);
      expect(find.byKey(_art), findsOneWidget);
      final stackedArt = tester.getRect(find.byKey(_art));
      final stackedTitle = tester.getRect(find.byKey(_title));
      expect(stackedArt.bottom, lessThanOrEqualTo(stackedTitle.top));
      expect(tester.takeException(), isNull);

      await _pumpAudio(tester, const Size(1280, 300), _audio(art: true));
      expect(find.byKey(_side), findsOneWidget);
      expect(find.byKey(_stacked), findsNothing);
      final sideArt = tester.getRect(find.byKey(_art));
      final sideTitle = tester.getRect(find.byKey(_title));
      expect(sideArt.right, lessThanOrEqualTo(sideTitle.left));
      expect(tester.takeException(), isNull);

      await _pumpAudio(tester, const Size(480, 190), _audio());
      expect(find.byKey(_side), findsOneWidget);
      expect(find.byKey(_iconArt), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpAudio(tester, const Size(480, 150), _audio(art: true));
      expect(find.byKey(_text), findsOneWidget);
      expect(find.byKey(_art), findsNothing);
      expect(find.byKey(_iconArt), findsNothing);
      expect(tester.takeException(), isNull);
      report.pass('M20.2');
    });

    testWidgets('M20.3 narrow areas never go side by side', (tester) async {
      await _pumpAudio(tester, const Size(300, 320), _audio(art: true));
      expect(find.byKey(_side), findsNothing);
      expect(find.byKey(_text), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpAudio(tester, const Size(300, 720), _audio(art: true));
      expect(find.byKey(_side), findsNothing);
      expect(find.byKey(_stacked), findsOneWidget);
      expect(
        tester.getRect(find.byKey(_art)).width,
        lessThanOrEqualTo(300 - 48 - 64),
      );
      expect(tester.takeException(), isNull);
      report.pass('M20.3');
    });

    testWidgets('M20.4 scroll fallback absorbs content that cannot fit', (
      tester,
    ) async {
      await _pumpAudio(
        tester,
        const Size(200, 120),
        _audio(title: _longText, artist: _longText, album: _longText),
      );
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      report.pass('M20.4');
    });

    testWidgets('M20.5 album replaces the static caption', (tester) async {
      await _pumpAudio(tester, const Size(800, 600), _audio(album: 'Blue LP'));
      expect(tester.widget<Text>(find.byKey(_caption)).data, 'Blue LP');
      expect(find.text('Audio playback'), findsNothing);

      await _pumpAudio(tester, const Size(800, 600), _audio());
      expect(tester.widget<Text>(find.byKey(_caption)).data, 'Audio playback');

      await _pumpAudio(tester, const Size(800, 600), _audio(album: ''));
      expect(tester.widget<Text>(find.byKey(_caption)).data, 'Audio playback');

      await _pumpAudio(tester, const Size(480, 190), _audio(album: 'Side LP'));
      expect(tester.widget<Text>(find.byKey(_caption)).data, 'Side LP');

      await _pumpAudio(tester, const Size(300, 150), _audio(album: 'Tiny LP'));
      expect(tester.widget<Text>(find.byKey(_caption)).data, 'Tiny LP');
      report.pass('M20.5');
    });

    testWidgets('M20.6 title and artist are present in every layout', (
      tester,
    ) async {
      for (final size in const [
        Size(1280, 720),
        Size(1280, 300),
        Size(300, 150),
      ]) {
        await _pumpAudio(tester, size, _audio(art: true));
        expect(find.byKey(_title), findsOneWidget, reason: '$size');
        expect(find.byKey(_artist), findsOneWidget, reason: '$size');
        expect(find.text('Song Title'), findsOneWidget, reason: '$size');
        expect(find.text('The Artist'), findsOneWidget, reason: '$size');
      }
      await _pumpAudio(tester, const Size(800, 600), _audio(title: null));
      expect(find.text('some-file'), findsOneWidget);
      report.pass('M20.6');
    });

    test('M20.7 media-audio keys stay on the media surface wrappers', () {
      final text = File('lib/screens/player/widgets/media_surface.dart')
          .readAsStringSync();
      expect(text, contains("'media-audio-with-art'"));
      expect(text, contains("'media-audio'"));
      report.pass('M20.7');
    });
  });

  group('Finding 22: empty state', () {
    testWidgets('M22.1 never overflows at any size', (tester) async {
      const sizes = [
        Size(1280, 720),
        Size(800, 600),
        Size(480, 320),
        Size(300, 300),
        Size(200, 200),
      ];
      for (final size in sizes) {
        for (final recent in [0, 3, 8]) {
          for (final dismissed in [false, true]) {
            await _pumpEmpty(
              tester,
              size,
              _empty(tipDismissed: dismissed, recent: _recents(recent)),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size recent=$recent dismissed=$dismissed',
            );
          }
        }
      }
      report.pass('M22.1');
    });

    testWidgets('M22.2 one filled primary and lighter secondaries', (
      tester,
    ) async {
      await _pumpEmpty(
        tester,
        const Size(800, 600),
        _empty(recent: _recents(2)),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      final primary = find.byKey(const Key('open-file-empty-button'));
      expect(primary, findsOneWidget);
      expect(tester.widget(primary), isA<FilledButton>());
      for (final key in const [
        'open-folder-empty-button',
        'open-playlist-empty-button',
        'open-url-empty-button',
        'reopen-last-empty-button',
      ]) {
        final widget = tester.widget(find.byKey(Key(key)));
        expect(widget, isA<TextButton>(), reason: key);
        expect(widget, isNot(isA<FilledButton>()), reason: key);
      }
      report.pass('M22.2');
    });

    testWidgets('M22.3 existing keys fire their own callbacks', (tester) async {
      final log = <String>[];
      await _pumpEmpty(
        tester,
        const Size(800, 600),
        _empty(recent: _recents(1), log: log),
      );
      const expectations = {
        'open-file-empty-button': 'file',
        'open-folder-empty-button': 'folder',
        'open-playlist-empty-button': 'playlist',
        'open-url-empty-button': 'url',
        'reopen-last-empty-button': 'reopen',
        'empty-state-tip-dismiss': 'dismiss',
      };
      for (final entry in expectations.entries) {
        log.clear();
        final finder = find.byKey(Key(entry.key));
        expect(finder, findsOneWidget, reason: entry.key);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
        expect(log, [entry.value], reason: entry.key);
      }
      report.pass('M22.3');
    });

    testWidgets('M22.4 reopen last only with recent files', (tester) async {
      await _pumpEmpty(tester, const Size(800, 600), _empty());
      expect(find.byKey(const Key('reopen-last-empty-button')), findsNothing);
      expect(find.text('Reopen Last'), findsNothing);
      expect(find.byKey(const Key('open-folder-empty-button')), findsOneWidget);

      await _pumpEmpty(
        tester,
        const Size(800, 600),
        _empty(recent: _recents(1)),
      );
      expect(find.byKey(const Key('reopen-last-empty-button')), findsOneWidget);
      report.pass('M22.4');
    });

    testWidgets('M22.5 recent list is capped at five and labelled', (
      tester,
    ) async {
      final recent = _recents(8);
      await _pumpEmpty(tester, const Size(800, 900), _empty(recent: recent));
      for (var i = 0; i < 5; i++) {
        final row = find.byKey(Key('empty-recent-$i'));
        expect(row, findsOneWidget, reason: 'row $i');
        expect(
          find.descendant(of: row, matching: find.text('track$i.mp3')),
          findsOneWidget,
        );
        expect(find.byTooltip(recent[i]), findsOneWidget, reason: 'tip $i');
      }
      expect(find.byKey(const Key('empty-recent-5')), findsNothing);
      expect(find.byKey(const Key('empty-recent-7')), findsNothing);
      expect(find.byTooltip(recent[5]), findsNothing);
      final tops = [
        for (var i = 0; i < 5; i++)
          tester.getTopLeft(find.byKey(Key('empty-recent-$i'))).dy,
      ];
      expect(tops, [...tops]..sort());

      await _pumpEmpty(
        tester,
        const Size(800, 900),
        _empty(recent: _recents(2)),
      );
      expect(find.byKey(const Key('empty-recent-1')), findsOneWidget);
      expect(find.byKey(const Key('empty-recent-2')), findsNothing);
      report.pass('M22.5');
    });

    testWidgets('M22.6 tapping a recent row opens that path only', (
      tester,
    ) async {
      final log = <String>[];
      final recent = _recents(4);
      await _pumpEmpty(
        tester,
        const Size(800, 900),
        _empty(recent: recent, log: log),
      );
      final row = find.byKey(const Key('empty-recent-2'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(log, ['recent:${recent[2]}']);
      report.pass('M22.6');
    });

    testWidgets('M22.7 no recent files means no list', (tester) async {
      await _pumpEmpty(tester, const Size(800, 900), _empty());
      expect(find.byKey(const Key('empty-recent-0')), findsNothing);
      expect(find.text('Recent'), findsNothing);

      await _pumpEmpty(
        tester,
        const Size(800, 900),
        _empty(recent: _recents(1)),
      );
      expect(find.text('Recent'), findsOneWidget);
      report.pass('M22.7');
    });

    testWidgets('M22.8 tip shows until dismissed', (tester) async {
      final log = <String>[];
      await _pumpEmpty(tester, const Size(800, 600), _empty(log: log));
      expect(find.textContaining('Tip: Reopen Last'), findsOneWidget);
      final dismiss = find.byKey(const Key('empty-state-tip-dismiss'));
      expect(dismiss, findsOneWidget);
      await tester.ensureVisible(dismiss);
      await tester.tap(dismiss);
      await tester.pump();
      expect(log, ['dismiss']);

      await _pumpEmpty(
        tester,
        const Size(800, 600),
        _empty(tipDismissed: true),
      );
      expect(find.textContaining('Tip: Reopen Last'), findsNothing);
      expect(find.byKey(const Key('empty-state-tip-dismiss')), findsNothing);
      report.pass('M22.8');
    });

    testWidgets('M22.9 primary action is on screen at 480x320', (tester) async {
      await _pumpEmpty(
        tester,
        const Size(480, 320),
        _empty(recent: _recents(5)),
      );
      final rect = tester.getRect(
        find.byKey(const Key('open-file-empty-button')),
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(320));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
      report.pass('M22.9');
    });
  });
}
