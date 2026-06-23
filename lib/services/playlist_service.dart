import 'dart:math';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/playable_source.dart';

/// In-memory playback queue. Persistence is intentionally omitted: queue lives
/// for the session. The `index` is `-1` when the queue is empty.
class PlaylistService extends ChangeNotifier {
  /// Maximum tracks kept in memory for one session (bulk folder drops).
  static const int maxQueueItems = 1000;

  final List<PlayableSource> _items = [];
  int _index = -1;
  bool _shuffle = false;
  final List<int> _shuffleOrder = [];
  int _shufflePos = -1;
  bool _disposed = false;

  List<PlayableSource> get items => List.unmodifiable(_items);
  int get index => _index;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  PlayableSource? get current =>
      (_index >= 0 && _index < _items.length) ? _items[_index] : null;
  bool get shuffle => _shuffle;
  bool get hasNext => _peekRelative(1) != null;
  bool get hasPrevious => _peekRelative(-1) != null;

  void setShuffle(bool value) {
    if (_shuffle == value) return;
    _shuffle = value;
    _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
  }

  /// Replaces the queue and starts at [startIndex] (default 0).
  /// Returns how many paths were dropped because of [maxQueueItems].
  int replace(List<String> paths, {int startIndex = 0}) {
    return replaceSources(
      paths.map(PlayableSource.file).toList(growable: false),
      startIndex: startIndex,
    );
  }

  /// Replaces the queue with typed media sources.
  /// Returns how many sources were dropped because of [maxQueueItems].
  int replaceSources(List<PlayableSource> sources, {int startIndex = 0}) {
    final filtered = sources
        .where((source) => source.value.trim().isNotEmpty)
        .toList();
    final capped = filtered.length > maxQueueItems
        ? filtered.sublist(0, maxQueueItems)
        : filtered;
    final dropped = filtered.length - capped.length;
    _items
      ..clear()
      ..addAll(capped);
    if (_items.isEmpty) {
      _index = -1;
    } else {
      _index = startIndex.clamp(0, _items.length - 1);
    }
    if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
    return dropped;
  }

  /// Appends [paths] to the queue.
  /// Returns how many paths were dropped because of [maxQueueItems].
  int addAll(List<String> paths) {
    return addAllSources(
      paths.map(PlayableSource.file).toList(growable: false),
    );
  }

  /// Appends typed media sources to the queue.
  /// Returns how many sources were dropped because of [maxQueueItems].
  int addAllSources(List<PlayableSource> sources) {
    final filtered = sources
        .where((source) => source.value.trim().isNotEmpty)
        .toList();
    if (filtered.isEmpty) return 0;
    final room = maxQueueItems - _items.length;
    if (room <= 0) return filtered.length;
    final toAdd = filtered.length > room ? filtered.sublist(0, room) : filtered;
    final dropped = filtered.length - toAdd.length;
    final wasEmpty = _items.isEmpty;
    _items.addAll(toAdd);
    if (wasEmpty) _index = 0;
    if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
    return dropped;
  }

  /// Inserts [path] right after the current item.
  void playNext(String path) => playNextSource(PlayableSource.file(path));

  void playNextSource(PlayableSource source) {
    if (source.value.trim().isEmpty) return;
    if (_items.isEmpty) {
      _items.add(source);
      _index = 0;
    } else {
      _items.insert(_index + 1, source);
    }
    if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
  }

  void removeAt(int i) {
    if (i < 0 || i >= _items.length) return;
    _items.removeAt(i);
    if (_items.isEmpty) {
      _index = -1;
    } else if (i < _index) {
      _index--;
    } else if (i == _index && _index >= _items.length) {
      _index = _items.length - 1;
    }
    if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
  }

  Future<int> removeMissingFiles() async {
    if (_items.isEmpty || _disposed) return 0;
    final checkedPaths = _items
        .where((source) => source.isFile)
        .map((source) => source.value)
        .toSet();
    if (checkedPaths.isEmpty) return 0;
    final pathsToCheck = checkedPaths.toList(growable: false);
    final existingPaths = (await Isolate.run(
      () => _existingFilePaths(pathsToCheck),
    )).toSet();
    if (_disposed) return 0;
    final missingPaths = checkedPaths.difference(existingPaths);
    if (missingPaths.isEmpty) return 0;
    final current = this.current;
    final before = _items.length;
    _items.removeWhere(
      (source) => source.isFile && missingPaths.contains(source.value),
    );
    final removed = before - _items.length;
    if (removed == 0) return 0;
    if (_items.isEmpty) {
      _index = -1;
    } else if (current != null) {
      final nextIndex = _items.indexOf(current);
      _index = nextIndex >= 0 ? nextIndex : _index.clamp(0, _items.length - 1);
    } else {
      _index = _index.clamp(0, _items.length - 1);
    }
    if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
    return removed;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _index = -1;
    _shuffleOrder.clear();
    _shufflePos = -1;
    notifyListeners();
  }

  void jumpTo(int i) {
    if (i < 0 || i >= _items.length) return;
    _index = i;
    if (_shuffle) {
      _shufflePos = _shuffleOrder.indexOf(i);
      if (_shufflePos < 0) _rebuildShuffleOrder(preserveCurrent: true);
    }
    notifyListeners();
  }

  /// Advances by [delta] in queue order. Returns the new path or null when out
  /// of bounds. Honors shuffle.
  PlayableSource? advance(int delta) {
    if (_items.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleOrder.isEmpty) return null;
      final pos = _shufflePos + delta;
      if (pos < 0 || pos >= _shuffleOrder.length) return null;
      _shufflePos = pos;
      _index = _shuffleOrder[pos];
      notifyListeners();
      return _items[_index];
    }
    final ni = _index + delta;
    if (ni < 0 || ni >= _items.length) return null;
    _index = ni;
    notifyListeners();
    return _items[_index];
  }

  PlayableSource? _peekRelative(int delta) {
    if (_items.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleOrder.isEmpty) return null;
      final pos = _shufflePos + delta;
      if (pos < 0 || pos >= _shuffleOrder.length) return null;
      return _items[_shuffleOrder[pos]];
    }
    final ni = _index + delta;
    if (ni < 0 || ni >= _items.length) return null;
    return _items[ni];
  }

  void _rebuildShuffleOrder({bool preserveCurrent = true}) {
    if (!_shuffle || _items.isEmpty) {
      _shuffleOrder.clear();
      _shufflePos = -1;
      return;
    }
    final indices = List<int>.generate(_items.length, (i) => i);
    indices.shuffle(Random());
    if (preserveCurrent && _index >= 0 && _index < _items.length) {
      // Find the current index in the shuffled list and swap it to slot 0,
      // avoiding the O(n) cost of List.remove + List.insert(0).
      final pos = indices.indexOf(_index);
      if (pos > 0) {
        indices[pos] = indices[0];
        indices[0] = _index;
      }
    }
    _shuffleOrder
      ..clear()
      ..addAll(indices);
    _shufflePos = preserveCurrent ? 0 : -1;
  }
}

List<String> _existingFilePaths(List<String> paths) {
  final existing = <String>[];
  for (final path in paths) {
    try {
      if (File(path).existsSync()) existing.add(path);
    } catch (_) {
      // Treat inaccessible paths as missing.
    }
  }
  return existing;
}
