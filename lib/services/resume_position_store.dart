import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class ResumeEntry {
  final int positionMs;
  final int lastAccessMs;
  const ResumeEntry({required this.positionMs, required this.lastAccessMs});
}

abstract class ResumePositionStore {
  Map<String, ResumeEntry> load();

  Future<Map<String, ResumeEntry>> save(
    Map<String, ResumeEntry> entries, {
    Set<String> removed = const {},
  });

  Future<void> clear();

  static Map<String, ResumeEntry> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, ResumeEntry>{};
    try {
      var decoded = jsonDecode(raw);
      if (decoded is Map && decoded['entries'] is Map) {
        decoded = decoded['entries'];
      }
      if (decoded is! Map) return <String, ResumeEntry>{};
      final result = <String, ResumeEntry>{};
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          final p = value['p'];
          final t = value['t'];
          if (p is int && p > 0 && t is int && t > 0) {
            result[key] = ResumeEntry(positionMs: p, lastAccessMs: t);
          }
        }
      });
      return result;
    } catch (_) {
      return <String, ResumeEntry>{};
    }
  }

  static Map<String, Map<String, int>> encodeEntries(
    Map<String, ResumeEntry> entries,
  ) => {
    for (final entry in entries.entries)
      entry.key: {'p': entry.value.positionMs, 't': entry.value.lastAccessMs},
  };
}

class PrefsResumePositionStore implements ResumePositionStore {
  PrefsResumePositionStore(this._prefs);

  static const key = 'resume_positions_v2';

  final SharedPreferences _prefs;

  @override
  Map<String, ResumeEntry> load() =>
      ResumePositionStore.decode(_prefs.getString(key));

  @override
  Future<Map<String, ResumeEntry>> save(
    Map<String, ResumeEntry> entries, {
    Set<String> removed = const {},
  }) async {
    if (entries.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(
        key,
        jsonEncode(ResumePositionStore.encodeEntries(entries)),
      );
    }
    return Map<String, ResumeEntry>.of(entries);
  }

  @override
  Future<void> clear() => _prefs.remove(key);
}

class FileResumePositionStore implements ResumePositionStore {
  FileResumePositionStore(this.path, {this.maxEntries = 100});

  final String path;
  final int maxEntries;

  @override
  Map<String, ResumeEntry> load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return <String, ResumeEntry>{};
      return ResumePositionStore.decode(file.readAsStringSync());
    } catch (_) {
      return <String, ResumeEntry>{};
    }
  }

  @override
  Future<Map<String, ResumeEntry>> save(
    Map<String, ResumeEntry> entries, {
    Set<String> removed = const {},
  }) async {
    final merged = load()..removeWhere((key, _) => removed.contains(key));
    entries.forEach((key, local) {
      final disk = merged[key];
      if (disk == null || local.lastAccessMs >= disk.lastAccessMs) {
        merged[key] = local;
      }
    });
    if (merged.length > maxEntries) {
      final ordered = merged.entries.toList()
        ..sort((a, b) => a.value.lastAccessMs.compareTo(b.value.lastAccessMs));
      final overflow = merged.length - maxEntries;
      for (var i = 0; i < overflow; i++) {
        merged.remove(ordered[i].key);
      }
    }
    _writeAtomically(
      jsonEncode({
        'v': 1,
        'entries': ResumePositionStore.encodeEntries(merged),
      }),
    );
    return merged;
  }

  @override
  Future<void> clear() async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  void _writeAtomically(String contents) {
    final target = File(path);
    target.parent.createSync(recursive: true);
    final temp = File('$path.$pid.tmp');
    try {
      temp.writeAsStringSync(contents, flush: true);
      temp.renameSync(path);
    } catch (_) {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }
}
