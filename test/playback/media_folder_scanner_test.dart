import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/playback/media_folder_scanner.dart';

void main() {
  String relFrom(String root, String fullPath) {
    return p.relative(fullPath, from: root).replaceAll('\\', '/');
  }

  group('MediaFolderScanner', () {
    test('recursively keeps supported media and sorts paths', () async {
      final dir = Directory.systemTemp.createTempSync('dacx_scan_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/nested').createSync();
      File('${dir.path}/z.mp3').writeAsStringSync('z');
      File('${dir.path}/nested/a.mkv').writeAsStringSync('a');
      File('${dir.path}/notes.txt').writeAsStringSync('skip');

      final result = await MediaFolderScanner.scan(dir.path);

      expect(result.skipped, 1);
      expect(result.truncated, 0);
      expect(result.paths.map((path) => relFrom(dir.path, path)), [
        'nested/a.mkv',
        'z.mp3',
      ]);
    });

    test('caps results and reports truncation', () async {
      final dir = Directory.systemTemp.createTempSync('dacx_scan_cap_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < 5; i++) {
        File('${dir.path}/$i.mp3').writeAsStringSync('$i');
      }

      final result = await MediaFolderScanner.scan(dir.path, maxItems: 3);

      expect(result.paths.length, 3);
      expect(result.truncated, 2);
      expect(result.paths.map((path) => relFrom(dir.path, path)), [
        '0.mp3',
        '1.mp3',
        '2.mp3',
      ]);
    });

    test('returns empty result when folder is missing', () async {
      final dir = Directory.systemTemp.createTempSync('dacx_scan_missing_');
      final missingPath = '${dir.path}/gone';
      addTearDown(() => dir.deleteSync(recursive: true));

      final result = await MediaFolderScanner.scan(missingPath);

      expect(result.paths, isEmpty);
      expect(result.skipped, 0);
      expect(result.truncated, 0);
    });

    test('sorts paths with natural/numeric ordering', () async {
      final dir = Directory.systemTemp.createTempSync('dacx_scan_nat_sort_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Create files with unpadded track numbers.
      for (final name in [
        'track10.mp3',
        'track2.mp3',
        'track1.mp3',
        'track20.mp3',
      ]) {
        File('${dir.path}/$name').writeAsStringSync(name);
      }

      final result = await MediaFolderScanner.scan(dir.path);

      expect(result.paths.map((path) => relFrom(dir.path, path)), [
        'track1.mp3',
        'track2.mp3',
        'track10.mp3',
        'track20.mp3',
      ]);
    });
  });
}
