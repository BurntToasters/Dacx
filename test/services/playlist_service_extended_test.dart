import 'package:dacx/services/playlist_service.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistService', () {
    late PlaylistService service;

    setUp(() {
      service = PlaylistService();
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is empty', () {
      expect(service.isEmpty, isTrue);
      expect(service.isNotEmpty, isFalse);
      expect(service.length, 0);
      expect(service.index, -1);
      expect(service.current, isNull);
      expect(service.hasNext, isFalse);
      expect(service.hasPrevious, isFalse);
    });

    test('replace sets queue and index', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
      expect(service.length, 3);
      expect(service.index, 0);
      expect(service.current?.value, '/a.mp3');
    });

    test('replace with startIndex', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3'], startIndex: 2);
      expect(service.index, 2);
      expect(service.current?.value, '/c.mp3');
    });

    test('replace clamps startIndex', () {
      service.replace(['/a.mp3'], startIndex: 99);
      expect(service.index, 0);
    });

    test('replace filters empty paths', () {
      service.replace(['/a.mp3', '', '  ', '/b.mp3']);
      expect(service.length, 2);
    });

    test('replace returns dropped count over max', () {
      final paths = List.generate(1005, (i) => '/file$i.mp3');
      final dropped = service.replace(paths);
      expect(dropped, 5);
      expect(service.length, PlaylistService.maxQueueItems);
    });

    test('addAll appends to queue', () {
      service.replace(['/a.mp3']);
      service.addAll(['/b.mp3', '/c.mp3']);
      expect(service.length, 3);
      expect(service.index, 0); // Unchanged
    });

    test('addAll sets index to 0 when queue was empty', () {
      service.addAll(['/a.mp3']);
      expect(service.index, 0);
      expect(service.current?.value, '/a.mp3');
    });

    test('addAll returns dropped count when full', () {
      service.replace(List.generate(999, (i) => '/f$i.mp3'));
      final dropped = service.addAll(['/x.mp3', '/y.mp3']);
      expect(dropped, 1);
      expect(service.length, PlaylistService.maxQueueItems);
    });

    test('playNext inserts after current', () {
      service.replace(['/a.mp3', '/c.mp3']);
      service.playNext('/b.mp3');
      expect(service.items[1].value, '/b.mp3');
      expect(service.items[2].value, '/c.mp3');
    });

    test('playNext on empty creates queue', () {
      service.playNext('/a.mp3');
      expect(service.length, 1);
      expect(service.index, 0);
    });

    test('removeAt removes item and adjusts index', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3'], startIndex: 1);
      service.removeAt(0); // Remove before current
      expect(service.index, 0);
      expect(service.current?.value, '/b.mp3');
    });

    test('removeAt current adjusts to valid index', () {
      service.replace(['/a.mp3', '/b.mp3']);
      service.jumpTo(1);
      service.removeAt(1);
      expect(service.index, 0);
    });

    test('removeAt last item empties queue', () {
      service.replace(['/a.mp3']);
      service.removeAt(0);
      expect(service.isEmpty, isTrue);
      expect(service.index, -1);
    });

    test('removeAt out of bounds does nothing', () {
      service.replace(['/a.mp3']);
      service.removeAt(-1);
      service.removeAt(5);
      expect(service.length, 1);
    });

    test('jumpTo changes index', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
      service.jumpTo(2);
      expect(service.index, 2);
      expect(service.current?.value, '/c.mp3');
    });

    test('jumpTo out of bounds does nothing', () {
      service.replace(['/a.mp3']);
      service.jumpTo(5);
      expect(service.index, 0);
      service.jumpTo(-1);
      expect(service.index, 0);
    });

    test('advance forward', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
      final next = service.advance(1);
      expect(next?.value, '/b.mp3');
      expect(service.index, 1);
    });

    test('advance backward', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3'], startIndex: 2);
      final prev = service.advance(-1);
      expect(prev?.value, '/b.mp3');
      expect(service.index, 1);
    });

    test('advance past end returns null without wrap', () {
      service.replace(['/a.mp3', '/b.mp3'], startIndex: 1);
      expect(service.advance(1), isNull);
      expect(service.index, 1); // Unchanged
    });

    test('advance past end with wrap loops', () {
      service.replace(['/a.mp3', '/b.mp3'], startIndex: 1);
      final next = service.advance(1, wrap: true);
      expect(next?.value, '/a.mp3');
      expect(service.index, 0);
    });

    test('advance before start with wrap loops', () {
      service.replace(['/a.mp3', '/b.mp3'], startIndex: 0);
      final prev = service.advance(-1, wrap: true);
      expect(prev?.value, '/b.mp3');
      expect(service.index, 1);
    });

    test('hasNext and hasPrevious', () {
      service.replace(['/a.mp3', '/b.mp3', '/c.mp3'], startIndex: 1);
      expect(service.hasNext, isTrue);
      expect(service.hasPrevious, isTrue);
    });

    test('hasNext false at end', () {
      service.replace(['/a.mp3', '/b.mp3'], startIndex: 1);
      expect(service.hasNext, isFalse);
    });

    test('hasPrevious false at start', () {
      service.replace(['/a.mp3', '/b.mp3'], startIndex: 0);
      expect(service.hasPrevious, isFalse);
    });

    test('clear empties queue', () {
      service.replace(['/a.mp3', '/b.mp3']);
      service.clear();
      expect(service.isEmpty, isTrue);
      expect(service.index, -1);
    });

    test('clear on empty does not notify', () {
      var notified = false;
      service.addListener(() => notified = true);
      service.clear();
      expect(notified, isFalse);
    });

    group('shuffle', () {
      test('setShuffle enables shuffle mode', () {
        service.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
        service.setShuffle(true);
        expect(service.shuffle, isTrue);
      });

      test('advance in shuffle mode produces valid items', () {
        service.replace(List.generate(10, (i) => '/f$i.mp3'));
        service.setShuffle(true);
        final seen = <String>{service.current!.value};
        for (var i = 0; i < 9; i++) {
          final next = service.advance(1);
          expect(next, isNotNull);
          seen.add(next!.value);
        }
        // All should be valid paths
        expect(seen.length, lessThanOrEqualTo(10));
        for (final v in seen) {
          expect(v, startsWith('/f'));
        }
      });

      test('setShuffle(false) disables shuffle', () {
        service.replace(['/a.mp3', '/b.mp3']);
        service.setShuffle(true);
        service.setShuffle(false);
        expect(service.shuffle, isFalse);
      });

      test('jumpTo in shuffle mode works', () {
        service.replace(['/a.mp3', '/b.mp3', '/c.mp3']);
        service.setShuffle(true);
        service.jumpTo(2);
        expect(service.current?.value, '/c.mp3');
      });
    });

    test('replaceSources works with PlayableSource', () {
      service.replaceSources([
        PlayableSource.file('/a.mp3'),
        PlayableSource.url('https://stream.example.com/live'),
      ]);
      expect(service.length, 2);
      expect(service.items[0].isFile, isTrue);
      expect(service.items[1].isFile, isFalse);
    });

    test('playNextSource works', () {
      service.replace(['/a.mp3']);
      service.playNextSource(PlayableSource.url('https://x.com/b.mp3'));
      expect(service.items[1].value, 'https://x.com/b.mp3');
    });

    test('addAllSources works', () {
      final dropped = service.addAllSources([
        PlayableSource.file('/x.mp3'),
        PlayableSource.file('/y.mp3'),
      ]);
      expect(dropped, 0);
      expect(service.length, 2);
    });
  });
}
