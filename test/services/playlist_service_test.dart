import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/playlist_service.dart';

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
      expect(s.current, 'b');
    });

    test('replace filters empty/whitespace entries', () {
      final s = PlaylistService();
      s.replace(['a', '', '  ', 'b']);
      expect(s.items, ['a', 'b']);
    });

    test('replace clamps startIndex into bounds', () {
      final s = PlaylistService();
      s.replace(['a', 'b'], startIndex: 99);
      expect(s.index, 1);
    });

    test('addAll appends and seeds index when empty', () {
      final s = PlaylistService();
      s.addAll(['a', 'b']);
      expect(s.length, 2);
      expect(s.index, 0);
      s.addAll(['c']);
      expect(s.length, 3);
      expect(s.index, 0);
    });

    test('playNext inserts after current', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 0);
      s.playNext('x');
      expect(s.items, ['a', 'x', 'b', 'c']);
      expect(s.index, 0);
    });

    test('playNext on empty queue starts playback', () {
      final s = PlaylistService();
      s.playNext('only');
      expect(s.items, ['only']);
      expect(s.index, 0);
    });

    test('removeAt before current shifts index left', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 2);
      s.removeAt(0);
      expect(s.items, ['b', 'c']);
      expect(s.index, 1);
      expect(s.current, 'c');
    });

    test('removeAt of last current clamps to new last', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c'], startIndex: 2);
      s.removeAt(2);
      expect(s.items, ['a', 'b']);
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
      expect(s.advance(1), 'b');
      expect(s.index, 1);
      expect(s.advance(-1), 'a');
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
      expect(s.current, 'item7');
      expect(s.hasPrevious, isFalse);
    });

    test('shuffle covers every item in some order', () {
      final s = PlaylistService();
      final items = List.generate(10, (i) => 'i$i');
      s.replace(items, startIndex: 0);
      s.setShuffle(true);
      final visited = <String>{s.current!};
      for (var k = 0; k < items.length - 1; k++) {
        final next = s.advance(1);
        expect(next, isNotNull);
        visited.add(next!);
      }
      expect(visited.length, items.length);
      expect(s.advance(1), isNull);
    });

    test('disabling shuffle clears shuffle order', () {
      final s = PlaylistService();
      s.replace(['a', 'b', 'c']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.advance(1), 'b');
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
  });
}
