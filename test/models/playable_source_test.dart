import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';

void main() {
  group('PlayableSource', () {
    test('detects supported http and https URLs', () {
      expect(
        PlayableSource.isSupportedUrl('https://example.com/live.m3u8'),
        isTrue,
      );
      expect(
        PlayableSource.isSupportedUrl('http://example.com/radio.mp3'),
        isTrue,
      );
      expect(
        PlayableSource.isSupportedUrl('ftp://example.com/file.mp3'),
        isFalse,
      );
      expect(PlayableSource.isSupportedUrl('/tmp/file.mp3'), isFalse);
    });

    test('fromStored restores URLs and files', () {
      final url = PlayableSource.fromStored('https://example.com/live.m3u8');
      final file = PlayableSource.fromStored('/tmp/song.flac');

      expect(url?.isUrl, isTrue);
      expect(url?.displayName, 'live.m3u8');
      expect(file?.isFile, isTrue);
      expect(file?.displayName, 'song.flac');
    });

    test('detects and redacts non-display-safe URL parts', () {
      const signed =
          'https://user:pass@example.com/live.m3u8?token=secret#fragment';

      expect(
        PlayableSource.isDisplaySafeUrl('https://example.com/live.m3u8'),
        isTrue,
      );
      expect(PlayableSource.isDisplaySafeUrl(signed), isFalse);
      expect(
        PlayableSource.displaySafeUrl(signed),
        'https://example.com/live.m3u8?<redacted>#<redacted>',
      );
    });

    test('extension getter extracts from files and URLs', () {
      expect(PlayableSource.file('/tmp/song.flac').extension, 'flac');
      expect(PlayableSource.file('/tmp/noext').extension, '');
      expect(
        PlayableSource.url('https://example.com/stream.m3u8').extension,
        'm3u8',
      );
      expect(
        PlayableSource.url('https://example.com/stream.mp3?token=x').extension,
        'mp3',
      );
    });

    test('displayName falls back to host when URL has no path segments', () {
      final source = PlayableSource.url('https://radio.example.com');
      expect(source.displayName, 'radio.example.com');
    });

    test('equality and hashCode', () {
      final a = PlayableSource.file('/tmp/a.mp3');
      final b = PlayableSource.file('/tmp/a.mp3');
      final c = PlayableSource.url('https://example.com/a.mp3');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toString returns raw value', () {
      expect(PlayableSource.file('/tmp/a.mp3').toString(), '/tmp/a.mp3');
      expect(
        PlayableSource.url('https://example.com/x').toString(),
        'https://example.com/x',
      );
    });
  });
}
