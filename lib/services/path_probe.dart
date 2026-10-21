import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Filesystem existence checks that run off the UI isolate. A sync stat on a
/// stale network mount can block for seconds and freeze the app.
abstract final class PathProbe {
  /// Runs checks inline instead of in an isolate. Widget tests run in a
  /// fake-async zone where `Isolate.run` never completes.
  @visibleForTesting
  static bool runInline = false;

  /// Returns the subset of [paths] that exist as files.
  static Future<Set<String>> existingFiles(List<String> paths) async =>
      (await _run(paths, directories: false)).toSet();

  static Future<bool> fileExists(String path) async =>
      (await _run([path], directories: false)).isNotEmpty;

  static Future<bool> directoryExists(String path) async =>
      (await _run([path], directories: true)).isNotEmpty;

  static Future<bool> fileOrDirectoryExists(String path) async =>
      await fileExists(path) || await directoryExists(path);

  static Future<List<String>> _run(
    List<String> paths, {
    required bool directories,
  }) async {
    if (paths.isEmpty) return const [];
    final copy = List<String>.of(paths, growable: false);
    if (runInline) return _existing(copy, directories: directories);
    return Isolate.run(() => _existing(copy, directories: directories));
  }
}

List<String> _existing(List<String> paths, {required bool directories}) {
  final existing = <String>[];
  for (final path in paths) {
    try {
      final found = directories
          ? Directory(path).existsSync()
          : File(path).existsSync();
      if (found) existing.add(path);
    } catch (_) {
      // Treat inaccessible paths as missing.
    }
  }
  return existing;
}
