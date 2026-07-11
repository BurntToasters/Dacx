import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/playback/m3u_playlist.dart';

void main() {
  group('M3uPlaylist', () {
    test('detects playlist extensions', () {
      expect(M3uPlaylist.isPlaylistPath('/a/b/list.m3u'), isTrue);
      expect(M3uPlaylist.isPlaylistPath('/a/b/list.PLS'), isTrue);
      expect(M3uPlaylist.isPlaylistPath('/a/b/stream.m3u8'), isFalse);
      expect(M3uPlaylist.isPlaylistPath('/a/b/song.mp3'), isFalse);
    });

    test('parses m3u with relative paths and urls', () {
      final sources = M3uPlaylist.parse('''
#EXTM3U
#EXTINF:123,Track
one.mp3
https://example.com/two.flac
../up/three.ogg
''', baseDir: '/music/albums');
      expect(sources.map((s) => s.value).toList(), [
        p.normalize('/music/albums/one.mp3'),
        'https://example.com/two.flac',
        p.normalize('/music/up/three.ogg'),
      ]);
    });

    test('skips comments, blanks, and credential urls', () {
      final sources = M3uPlaylist.parse('''
# comment

https://user:pass@evil.example/x.mp3
/safe/track.mp3
''');
      expect(sources, hasLength(1));
      expect(sources.single.value, '/safe/track.mp3');
    });

    test('parses pls FileN entries in order', () {
      final sources = M3uPlaylist.parse('''
[playlist]
File2=b.mp3
Title2=B
File1=a.mp3
NumberOfEntries=2
''', baseDir: '/q');
      expect(sources.map((s) => s.value).toList(), [
        p.normalize('/q/a.mp3'),
        p.normalize('/q/b.mp3'),
      ]);
    });

    test('parseFile reads disk playlist', () async {
      final dir = await Directory.systemTemp.createTemp('dacx-m3u-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final playlist = File(p.join(dir.path, 'mix.m3u'));
      await playlist.writeAsString('local.wav\nhttps://cdn.example/x.mp3\n');
      final sources = await M3uPlaylist.parseFile(playlist.path);
      expect(sources, hasLength(2));
      expect(sources.first.value, p.join(dir.path, 'local.wav'));
      expect(sources.last.value, 'https://cdn.example/x.mp3');
    });
  });
}
