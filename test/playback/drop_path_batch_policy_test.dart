import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/drop_path_batch_policy.dart';

void main() {
  group('DropPathBatchPolicy.fromRawPaths', () {
    test('filters empty paths and counts skipped entries', () {
      final batch = DropPathBatchPolicy.fromRawPaths(
        rawPaths: [' /media/a.mp3 ', '', '  '],
        windows: false,
      );

      expect(batch.paths, ['/media/a.mp3']);
      expect(batch.skippedCount, 2);
      expect(batch.isEmpty, isFalse);
    });

    test('returns empty batch when every path is blank', () {
      final batch = DropPathBatchPolicy.fromRawPaths(
        rawPaths: ['', '   '],
        windows: false,
      );

      expect(batch.paths, isEmpty);
      expect(batch.skippedCount, 2);
      expect(batch.isEmpty, isTrue);
    });

    test('preserves multiple valid paths in order', () {
      final batch = DropPathBatchPolicy.fromRawPaths(
        rawPaths: ['/media/first.mp3', '/media/second.flac'],
        windows: false,
      );

      expect(batch.paths, ['/media/first.mp3', '/media/second.flac']);
      expect(batch.skippedCount, 0);
    });
  });
}
