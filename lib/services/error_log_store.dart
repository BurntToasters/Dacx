import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'instance_mode_service.dart';

/// Keeps error-level log lines on disk so a crash or quit still leaves a
/// record. Lines must already be redacted. Writes are synchronous and rare,
/// so the line is on disk before a crash can drop it.
class ErrorLogStore {
  static const String fileName = 'errors.log';
  static const int defaultMaxBytes = 256 * 1024;

  final String path;
  final int maxBytes;

  /// Errors written before this process started. Read once at construction,
  /// before this session appends, so the export can show what led to a crash.
  String get previousSessions => _previousSessions;
  String _previousSessions;

  ErrorLogStore(this.path, {this.maxBytes = defaultMaxBytes})
    : _previousSessions = _readAll(path);

  /// Stores the log next to the instance-mode flag, in the per-user app data
  /// folder for each platform.
  factory ErrorLogStore.forCurrentUser() => ErrorLogStore(
    p.join(p.dirname(InstanceModeService.flagFilePath()), fileName),
  );

  String get rotatedPath => '$path.1';

  void append(String line) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() >= maxBytes) {
        // Keep one older generation so rotation never drops the newest errors.
        file.renameSync(rotatedPath);
      }
      file.writeAsStringSync(
        '${line.replaceAll('\n', r'\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Never let error logging throw back into an error handler.
      if (kDebugMode) {
        debugPrint('Dacx: error log append failed: $e');
      }
    }
  }

  /// Deletes stored errors, including the history shown in exports.
  void clear() {
    _previousSessions = '';
    for (final candidate in [path, rotatedPath]) {
      try {
        final file = File(candidate);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // Best-effort; a leftover file only means older errors stay visible.
      }
    }
  }

  static String _readAll(String path) {
    final parts = <String>[];
    for (final candidate in ['$path.1', path]) {
      try {
        final file = File(candidate);
        if (file.existsSync()) parts.add(file.readAsStringSync().trimRight());
      } catch (_) {
        // Unreadable history is not worth failing startup over.
      }
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }
}
