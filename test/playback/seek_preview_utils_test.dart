import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/seek_preview_utils.dart';

void main() {
  group('SeekPreviewUtils.quantizeMs', () {
    test('rounds down to quantum buckets', () {
      expect(SeekPreviewUtils.quantizeMs(0), 0);
      expect(SeekPreviewUtils.quantizeMs(999), 0);
      expect(SeekPreviewUtils.quantizeMs(1000), 1000);
      expect(SeekPreviewUtils.quantizeMs(1500), 1000);
      expect(SeekPreviewUtils.quantizeMs(5999), 5000);
    });

    test('supports custom quantum sizes', () {
      expect(SeekPreviewUtils.quantizeMs(749, quantumMs: 250), 500);
      expect(SeekPreviewUtils.quantizeMs(1250, quantumMs: 500), 1000);
    });
  });

  group('SeekPreviewLruCache', () {
    test('returns null for missing keys', () {
      final cache = SeekPreviewLruCache<String, int>(2);
      expect(cache.get('missing'), isNull);
    });

    test('evicts least-recently-used entry at capacity', () {
      final cache = SeekPreviewLruCache<String, int>(2);
      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.get('a'), 1);
      cache.put('c', 3);
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
      expect(cache.get('c'), 3);
      expect(cache.length, 2);
    });

    test('clear removes all entries', () {
      final cache = SeekPreviewLruCache<int, int>(4);
      cache.put(1, 10);
      cache.put(2, 20);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.get(1), isNull);
    });
  });
}
