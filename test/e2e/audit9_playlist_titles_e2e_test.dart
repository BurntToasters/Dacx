import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/m3u_playlist.dart';
import 'package:dacx/screens/player/widgets/play_queue_drawer.dart';
import 'package:dacx/services/playlist_service.dart';
import 'package:dacx/theme/window_visuals.dart';

import '../support/audit9_report.dart';

String _c(int codePoint) => String.fromCharCode(codePoint);

final _bom = _c(0xFEFF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'playlist-titles',
    expectedIds: [for (var i = 1; i <= 12; i++) 'M45.$i'],
  );

  tearDownAll(report.write);

  group('Finding 45: playlist titles', () {
    test('M45.1 an EXTINF title sets the title of the entry that follows', () {
      final sources = M3uPlaylist.parse('''
#EXTM3U
#EXTINF:123,Artist - Song
https://cdn.example/a.mp3
''');
      expect(sources, hasLength(1));
      expect(sources.single.title, 'Artist - Song');
      report.pass('M45.1');
    });

    test('M45.2 an EXTINF title applies to one entry only', () {
      final single = M3uPlaylist.parse('''
#EXTINF:1,Only
https://cdn.example/a.mp3
https://cdn.example/b.mp3
''');
      expect(single.map((s) => s.title).toList(), ['Only', null]);

      final replaced = M3uPlaylist.parse('''
#EXTINF:1,Stale
#EXTINF:2,Fresh
https://cdn.example/a.mp3
''');
      expect(replaced.map((s) => s.title).toList(), ['Fresh']);
      report.pass('M45.2');
    });

    test('M45.3 an EXTINF title before a rejected entry is consumed', () {
      final sources = M3uPlaylist.parse('''
#EXTINF:1,Rejected
https://user:pass@cdn.example/x.mp3
https://cdn.example/good.mp3
''');
      expect(sources, hasLength(1));
      expect(sources.single.value, 'https://cdn.example/good.mp3');
      expect(sources.single.title, isNull);
      report.pass('M45.3');
    });

    test('M45.4 a comma inside quotes is not the title separator', () {
      final quoted = M3uPlaylist.parse('''
#EXTINF:-1 tvg-name="a,b",Real Title
https://cdn.example/a.mp3
''');
      expect(quoted.single.title, 'Real Title');

      final onlyQuoted = M3uPlaylist.parse('''
#EXTINF:-1 tvg-name="a,b"
https://cdn.example/a.mp3
''');
      expect(onlyQuoted.single.title, isNull);
      report.pass('M45.4');
    });

    test('M45.5 an EXTINF line without a title sets no title', () {
      for (final line in ['#EXTINF:123', '#EXTINF:123,', '#EXTINF:123,   ']) {
        final sources = M3uPlaylist.parse('$line\nhttps://cdn.example/a.mp3\n');
        expect(sources.single.title, isNull, reason: line);
      }
      report.pass('M45.5');
    });

    test('M45.6 PLS titles pair with the FileN of the same index', () {
      final paired = M3uPlaylist.parse('''
[playlist]
File2=https://cdn.example/2.mp3
Title2=Second
File1=https://cdn.example/1.mp3
Title1=First
NumberOfEntries=2
''');
      expect(paired.map((s) => s.value).toList(), [
        'https://cdn.example/1.mp3',
        'https://cdn.example/2.mp3',
      ]);
      expect(paired.map((s) => s.title).toList(), ['First', 'Second']);

      final unmatched = M3uPlaylist.parse('''
[playlist]
File1=https://cdn.example/1.mp3
Title3=Ghost
''');
      expect(unmatched, hasLength(1));
      expect(unmatched.single.title, isNull);

      final orphan = M3uPlaylist.parse('''
[playlist]
Title1=Ghost
''');
      expect(orphan, isEmpty);
      report.pass('M45.6');
    });

    test(
      'M45.7 titles drop control and bidi characters and collapse spaces',
      () {
        final source = PlayableSource.url(
          'https://cdn.example/a.mp3',
          title:
              'Bad${_c(0x01)}${_c(0x07)} ${_c(0x9F)} Title${_c(0x7F)}'
              '${_c(0x202E)}x${_c(0x2069)}\tTail   end',
        );
        expect(source.title, 'Bad Titlex Tail end');

        final m3u = M3uPlaylist.parse(
          '#EXTINF:1,Artist${_c(0x202A)} - Song${_c(0x07)}\n'
          'https://cdn.example/a.mp3\n',
        );
        expect(m3u.single.title, 'Artist - Song');

        final long = PlayableSource.url(
          'https://cdn.example/a.mp3',
          title: 'x' * 250,
        );
        expect(long.title, 'x' * 200);

        final emoji = PlayableSource.url(
          'https://cdn.example/a.mp3',
          title: String.fromCharCodes(List.filled(250, 0x1F600)),
        );
        expect(emoji.title!.runes.length, 200);
        expect(String.fromCharCodes(emoji.title!.runes), emoji.title);

        final blank = PlayableSource.url(
          'https://cdn.example/a.mp3',
          title: '${_c(0x01)}${_c(0x202E)}   ',
        );
        expect(blank.title, isNull);
        report.pass('M45.7');
      },
    );

    test('M45.8 the title does not affect equality or hash code', () {
      final titled = PlayableSource.file('/music/a.mp3', title: 'One');
      final other = PlayableSource.file('/music/a.mp3', title: 'Two');
      final plain = PlayableSource.file('/music/a.mp3');
      expect(titled, other);
      expect(titled, plain);
      expect(titled.hashCode, other.hashCode);
      expect(titled.hashCode, plain.hashCode);
      report.pass('M45.8');
    });

    test('M45.9 queueLabel is the title, or displayName without one', () {
      final titled = PlayableSource.file('/music/a.mp3', title: 'Song');
      expect(titled.queueLabel, 'Song');
      expect(titled.displayName, 'a.mp3');

      final plain = PlayableSource.file('/music/a.mp3');
      expect(plain.title, isNull);
      expect(plain.queueLabel, plain.displayName);
      report.pass('M45.9');
    });

    test('M45.10 encode writes titles and parse reads them back', () {
      final encoded = M3uPlaylist.encode([
        PlayableSource.file('/music/a.mp3', title: 'Artist - Song'),
        PlayableSource.url('https://cdn.example/b.mp3', title: 'Remote, Live'),
        PlayableSource.url('https://cdn.example/c.mp3'),
      ]);
      expect(encoded, startsWith('$_bom#EXTM3U\n'));
      expect(encoded, contains('#EXTINF:-1,Artist - Song\n/music/a.mp3\n'));
      expect(
        encoded,
        contains('#EXTINF:-1,Remote, Live\nhttps://cdn.example/b.mp3\n'),
      );

      final parsed = M3uPlaylist.parse(encoded);
      expect(parsed.map((s) => s.value).toList(), [
        '/music/a.mp3',
        'https://cdn.example/b.mp3',
        'https://cdn.example/c.mp3',
      ]);
      expect(parsed.map((s) => s.title).toList(), [
        'Artist - Song',
        'Remote, Live',
        null,
      ]);
      report.pass('M45.10');
    });

    test('M45.10 titles survive writeFile then parseFile twice', () async {
      final dir = await Directory.systemTemp.createTemp('dacx-m45-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = p.join(dir.path, 'a.mp3');
      final b = p.join(dir.path, 'b.mp3');
      File(a).writeAsBytesSync([0]);
      File(b).writeAsBytesSync([0]);

      final first = p.join(dir.path, 'first.m3u');
      await M3uPlaylist.writeFile(first, [
        PlayableSource.file(a, title: 'Artist - Song'),
        PlayableSource.file(b),
      ]);
      final loaded = await M3uPlaylist.parseFile(first);
      expect(loaded.map((s) => s.value).toList(), [a, b]);
      expect(loaded[0].title, 'Artist - Song');
      expect(loaded[1].title, isNull);

      final second = p.join(dir.path, 'second.m3u');
      await M3uPlaylist.writeFile(second, loaded);
      final again = await M3uPlaylist.parseFile(second);
      expect(again.map((s) => s.value).toList(), [a, b]);
      expect(again.map((s) => s.title).toList(), ['Artist - Song', null]);
      report.pass('M45.10');
    });

    test('M45.11 encode of an untitled playlist is unchanged', () {
      final encoded = M3uPlaylist.encode([
        PlayableSource.file('/music/a.mp3'),
        PlayableSource.url('https://cdn.example/b.mp3'),
      ]);
      expect(
        encoded,
        '$_bom#EXTM3U\n/music/a.mp3\nhttps://cdn.example/b.mp3\n',
      );
      report.pass('M45.11');
    });

    testWidgets('M45.12 the queue drawer shows the title of an entry', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final playlist = PlaylistService()
        ..replaceSources([
          PlayableSource.file('/music/a.mp3', title: 'Artist - Song'),
          PlayableSource.file('/music/b.mp3'),
        ]);
      addTearDown(playlist.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            extensions: [
              WindowVisuals.fromScheme(
                scheme,
                blurEnabled: false,
                blurStrength: 0,
              ),
            ],
          ),
          home: Scaffold(
            key: scaffoldKey,
            drawer: PlayQueueDrawer(
              playlist: playlist,
              hasCurrentFile: () => false,
              onShowMediaInfo: () {},
              onSetShuffle: (_) {},
              onClearQueue: () {},
              onActivateItem: (_) {},
              onRemoveItem: (_) {},
              onAddFiles: () {},
              onAddFolder: (_) {},
              onOpenPlaylist: (_) {},
              onSavePlaylist: () {},
              onRemoveMissing: () {},
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Artist - Song'), findsOneWidget);
      expect(find.text('a.mp3'), findsNothing);
      expect(find.text('b.mp3'), findsOneWidget);
      report.pass('M45.12');
    });
  });
}
