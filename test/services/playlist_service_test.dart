import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/services/playlist_service.dart';

List<String> _values(PlaylistService service) =>
    service.items.map((source) => source.value).toList(growable: false);

String? _currentValue(PlaylistService service) => service.current?.value;

void main() {
  group('PlaylistService basic queue ops', () {
    test('starts empty', () {
      final s = PlaylistService();
      expect(s.isEmpty, isTrue);
      expect(s.index, -1);
      expect(s.current, isNull);
      expect(s.hasNext, isFalse);
      expect(s.hasPrevious, isFalse);
    });

    test('replace populates queue and seeds index', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 1);
      expect(s.length, 3);
      expect(s.index, 1);
      expect(_currentValue(s), 'b');
    });

    test('replace filters empty/whitespace entries', () {
      final s = PlaylistService();
      s.replace(['a', '', '  ', 'b']);
      expect(_values(s), ['a', 'b']);
    });

    test('replace clamps startIndex into bounds', () {
      final s = PlaylistService();
      s.replace(['a', 'b'], startIndex: 99);
      expect(s.index, 1);
    });

    test('addAll appends and seeds index when empty', () {
      final s = PlaylistService();
      expect(s.addAll(['a', 'b']), 0);
      expect(s.length, 2);
      expect(s.index, 0);
      expect(s.addAll(['c']), 0);
      expect(s.length, 3);
      expect(s.index, 0);
    });

    test('replace and addAll cap at maxQueueItems', () {
      final s = PlaylistService();
      final many = List.generate(1005, (i) => '/track$i.mp3');
      expect(s.replace(many), 5);
      expect(s.length, PlaylistService.maxQueueItems);

      expect(s.addAll(List.generate(10, (i) => '/extra$i.mp3')), 10);
      expect(s.length, PlaylistService.maxQueueItems);
    });

    test('playNext inserts after current', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 0);
      s.playNext('x');
      expect(_values(s), ['a', 'x', 'b', 'c']);
      expect(s.index, 0);
    });

    test('playNext on empty queue starts playback', () {
      final s = PlaylistService();
      s.playNext('only');
      expect(_values(s), ['only']);
      expect(s.index, 0);
    });

    test('removeAt before current shifts index left', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 2);
      s.removeAt(0);
      expect(_values(s), ['b', 'c']);
      expect(s.index, 1);
      expect(_currentValue(s), 'c');
    });

    test('removeAt of last current clamps to new last', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 2);
      s.removeAt(2);
      expect(_values(s), ['a', 'b']);
      expect(s.index, 1);
    });

    test('clear empties queue and resets index', () {
      final s = PlaylistService();
      s.replace(['a', 'b']);
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.index, -1);
    });

    test('advance honors bounds and updates index', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 0);
      expect(s.advance(1)?.value, 'b');
      expect(s.index, 1);
      expect(s.advance(-1)?.value, 'a');
      expect(s.advance(-1), isNull);
      expect(s.index, 0);
      s.replace(['a', 'b'], startIndex: 1);
      expect(s.advance(1), isNull);
    });

    test('hasNext / hasPrevious reflect bounds', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 1);
      expect(s.hasNext, isTrue);
      expect(s.hasPrevious, isTrue);
      s.jumpTo(0);
      expect(s.hasPrevious, isFalse);
      s.jumpTo(2);
      expect(s.hasNext, isFalse);
    });

    test('jumpTo ignores out-of-range indices', () {
      final s = PlaylistService();
      s.replace(['a', 'b']);
      s.jumpTo(5);
      expect(s.index, 0);
      s.jumpTo(-1);
      expect(s.index, 0);
    });
  });

  group('PlaylistService shuffle', () {
    test('enabling shuffle keeps current item first in shuffle order', () {
      final s = PlaylistService();
      s.replace(List.generate(20, (i) => 'item$i'), startIndex: 7);
      s.setShuffle(true);
      expect(_currentValue(s), 'item7');
      expect(s.hasPrevious, isFalse);
    });

    test('shuffle covers every item in some order', () {
      final s = PlaylistService();
      final items = List.generate(10, (i) => 'i$i');
      s.replace(items, startIndex: 0);
      s.setShuffle(true);
      final visited = <String>{s.current!.value};
      for (var k = 0; k < items.length - 1; k++) {
        final next = s.advance(1);
        expect(next, isNotNull);
        visited.add(next!.value);
      }
      expect(visited.length, items.length);
      expect(s.advance(1), isNull);
    });

    test('disabling shuffle clears shuffle order', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.advance(1)?.value, 'b');
    });

    test('notifies listeners on mutation', () {
      final s = PlaylistService();
      var fired = 0;
      s.addListener(() => fired++);
      s.replace(['a']);
      s.addAll(['b']);
      s.removeAt(0);
      s.clear();
      expect(fired, greaterThanOrEqualTo(4));
    });

    test('supports mixed file and URL sources', () {
      final s = PlaylistService();
      s.replaceSources([
        PlayableSource.file('/tmp/local.mp3'),
        PlayableSource.url('https://example.com/live.m3u8'),
      ]);

      expect(s.current?.isFile, isTrue);
      expect(s.advance(1)?.isUrl, isTrue);
      expect(_values(s), ['/tmp/local.mp3', 'https://example.com/live.m3u8']);
    });

    test('removeMissingFiles drops missing files and keeps URLs', () async {
      final dir = Directory.systemTemp.createTempSync('dacx_playlist_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final existing = File('${dir.path}/keep.mp3')..writeAsStringSync('x');
      final missing = '${dir.path}/missing.mp3';
      final s = PlaylistService();
      s.replaceSources([
        PlayableSource.file(existing.path),
        PlayableSource.file(missing),
        PlayableSource.url('https://example.com/live.m3u8'),
      ]);

      expect(await s.removeMissingFiles(), 1);

      expect(_values(s), [existing.path, 'https://example.com/live.m3u8']);
    });
  });
}
