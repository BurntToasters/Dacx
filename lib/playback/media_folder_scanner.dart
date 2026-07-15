import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'player_path_utils.dart';

class MediaFolderScanResult {
  const MediaFolderScanResult({
    required this.paths,
    required this.skipped,
    required this.truncated,
  });

  final List<String> paths;
  final int skipped;
  final int truncated;
}

abstract final class MediaFolderScanner {
  static Future<MediaFolderScanResult> scan(
    String folderPath, {
    int maxItems = 1000,
  }) {
    return Isolate.run(() => _scanImpl(folderPath.trim(), maxItems));
  }
}

Future<MediaFolderScanResult> _scanImpl(String folderPath, int maxItems) async {
  final root = Directory(folderPath);
  if (!root.existsSync()) {
    return const MediaFolderScanResult(paths: [], skipped: 0, truncated: 0);
  }

  final limit = maxItems < 0 ? 0 : maxItems;
  final paths = <String>[];
  var skipped = 0;
  var supported = 0;
  var pathsAreSorted = false;
  final stream = root
      .list(recursive: true, followLinks: false)
      .handleError(
        (_) => skipped++,
        test: (error) => error is FileSystemException,
      );

  await for (final entity in stream) {
    if (entity is! File) continue;
    final path = entity.path.trim();
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (!PlayerPathUtils.isSupportedExtension(ext)) {
      skipped++;
      continue;
    }
    supported++;
    if (limit == 0) continue;
    if (paths.length < limit) {
      paths.add(path);
      if (paths.length == limit) {
        paths.sort(_comparePaths);
        pathsAreSorted = true;
      }
      continue;
    }
    if (!pathsAreSorted) {
      paths.sort(_comparePaths);
      pathsAreSorted = true;
    }
    if (_comparePaths(path, paths.last) >= 0) continue;
    final insertAt = _lowerBound(paths, path);
    paths.insert(insertAt, path);
    paths.removeLast();
  }

  if (!pathsAreSorted) {
    paths.sort(_comparePaths);
  }
  final truncated = supported > paths.length ? supported - paths.length : 0;
  return MediaFolderScanResult(
    paths: List<String>.unmodifiable(paths),
    skipped: skipped,
    truncated: truncated,
  );
}

int _comparePaths(String a, String b) {
  final natural = _naturalCompare(a.toLowerCase(), b.toLowerCase());
  // Deterministic tie-break for paths that differ only by case.
  return natural != 0 ? natural : a.compareTo(b);
}

/// Natural/numeric-aware comparison: digit runs are compared as integers so
/// "track2" sorts before "track10".
int _naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = ca >= 0x30 && ca <= 0x39;
    final bDigit = cb >= 0x30 && cb <= 0x39;
    if (aDigit && bDigit) {
      // Extract full digit runs from both sides.
      final aStart = i;
      final bStart = j;
      while (i < a.length &&
          a.codeUnitAt(i) >= 0x30 &&
          a.codeUnitAt(i) <= 0x39) {
        i++;
      }
      while (j < b.length &&
          b.codeUnitAt(j) >= 0x30 &&
          b.codeUnitAt(j) <= 0x39) {
        j++;
      }
      final aLen = i - aStart;
      final bLen = j - bStart;
      // Compare numerically: shorter digit run (sans leading zeros) is smaller.
      // Strip leading zeros for value comparison.
      var aNumStart = aStart;
      var bNumStart = bStart;
      while (aNumStart < i - 1 && a.codeUnitAt(aNumStart) == 0x30) {
        aNumStart++;
      }
      while (bNumStart < j - 1 && b.codeUnitAt(bNumStart) == 0x30) {
        bNumStart++;
      }
      final aEffLen = i - aNumStart;
      final bEffLen = j - bNumStart;
      if (aEffLen != bEffLen) return aEffLen - bEffLen;
      // Same effective length; compare digit by digit.
      for (var k = 0; k < aEffLen; k++) {
        final diff = a.codeUnitAt(aNumStart + k) - b.codeUnitAt(bNumStart + k);
        if (diff != 0) return diff;
      }
      // Same numeric value; shorter original (fewer leading zeros) wins.
      if (aLen != bLen) return aLen - bLen;
    } else {
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  return a.length - b.length;
}

int _lowerBound(List<String> sortedPaths, String path) {
  var low = 0;
  var high = sortedPaths.length;
  while (low < high) {
    final mid = low + ((high - low) >> 1);
    if (_comparePaths(sortedPaths[mid], path) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
