import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/playable_source.dart';
import 'path_probe.dart';

class PlaylistSnapshot {
  const PlaylistSnapshot({
    required this.items,
    required this.index,
    required this.shuffle,
    required this.shuffleOrder,
    required this.shufflePos,
  });

  final List<PlayableSource> items;
  final int index;
  final bool shuffle;
  final List<int> shuffleOrder;
  final int shufflePos;
}

/// In-memory playback queue. Snapshot persistence lives in [SettingsService];
/// this class itself only holds the live session state. The `index` is `-1`
/// when the queue is empty.
class PlaylistService extends ChangeNotifier {
  /// Maximum tracks kept in memory for one session (bulk folder drops).
  static const int maxQueueItems = 1000;

  final List<PlayableSource> _items = [];
  int _index = -1;
  bool _shuffle = false;
  final List<int> _shuffleOrder = [];
  int _shufflePos = -1;
  bool _disposed = false;
  int _revision = 0;

  List<PlayableSource> get items => List.unmodifiable(_items);
  int get revision => _revision;
  int get index => _index;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  PlayableSource? get current =>
      (_index >= 0 && _index < _items.length) ? _items[_index] : null;
  bool get shuffle => _shuffle;
  bool get hasNext => _peekRelative(1) != null;
  bool get hasPrevious => _peekRelative(-1) != null;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  PlaylistSnapshot capture() {
    return PlaylistSnapshot(
      items: List<PlayableSource>.of(_items),
      index: _index,
      shuffle: _shuffle,
      shuffleOrder: List<int>.of(_shuffleOrder),
      shufflePos: _shufflePos,
    );
  }

  void restore(PlaylistSnapshot snapshot) {
    _items
      ..clear()
      ..addAll(snapshot.items);
    _shuffle = snapshot.shuffle;
    _shuffleOrder
      ..clear()
      ..addAll(snapshot.shuffleOrder);
    _shufflePos = snapshot.shufflePos;
    if (_items.isEmpty) {
      _index = -1;
      _shuffleOrder.clear();
      _shufflePos = -1;
    } else if (snapshot.index < 0 || snapshot.index >= _items.length) {
      _index = 0;
    } else {
      _index = snapshot.index;
    }
    notifyListeners();
  }

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
    if (_shuffle) {
      wasEmpty
          ? _rebuildShuffleOrder(preserveCurrent: true)
          : _remapShuffleOrder((i) => i);
    }
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
      if (_shuffle) _rebuildShuffleOrder(preserveCurrent: true);
      notifyListeners();
      return;
    }
    int? evictedIndex;
    if (_items.length >= maxQueueItems) {
      // Evict the tail unless it is current. When current is already last,
      // evict the head and shift the current index before inserting after it.
      evictedIndex = _index + 1 >= _items.length ? 0 : _items.length - 1;
      _items.removeAt(evictedIndex);
      if (evictedIndex < _index) _index--;
    }
    final insertAt = _index + 1;
    _items.insert(insertAt, source);
    if (_shuffle) {
      _remapShuffleOrder((i) {
        if (i == evictedIndex) return null;
        final shifted = evictedIndex != null && i > evictedIndex ? i - 1 : i;
        return shifted >= insertAt ? shifted + 1 : shifted;
      }, playNext: insertAt);
    }
    notifyListeners();
  }

  /// Makes [source] the current queue item.
  ///
  /// If it is already in the queue, jumps to it. Otherwise replaces the queue
  /// with a single-item queue containing [source] so Open File / Open With /
  /// single-drop stays coherent with prev/next and completion advance.
  void setPlayingSource(PlayableSource source) {
    if (source.value.trim().isEmpty) return;
    final existing = _items.indexWhere((item) => item == source);
    if (existing >= 0) {
      jumpTo(existing);
      return;
    }
    replaceSources([source]);
  }

  /// Moves item at [oldIndex] to [newIndex] (ReorderableListView semantics).
  /// Reorders queue for [ReorderableListView.onReorderItem] (already-adjusted
  /// [newIndex]; no manual `newIndex -= 1` when moving downward).
  void moveItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    if (newIndex == oldIndex) return;
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    int moved(int i) {
      if (i == oldIndex) return newIndex;
      if (oldIndex < i && i <= newIndex) return i - 1;
      if (newIndex <= i && i < oldIndex) return i + 1;
      return i;
    }

    _index = moved(_index);
    if (_shuffle) _remapShuffleOrder(moved);
    notifyListeners();
  }

  void removeAt(int i) {
    if (i < 0 || i >= _items.length) return;
    final shuffleNext = _shuffle && i == _index ? _peekShuffleIndex(1) : null;
    _items.removeAt(i);
    int? removed(int k) => k == i ? null : (k > i ? k - 1 : k);
    if (_items.isEmpty) {
      _index = -1;
    } else if (shuffleNext != null) {
      _index = removed(shuffleNext)!;
    } else if (i < _index) {
      _index--;
    } else if (i == _index && _index >= _items.length) {
      _index = _items.length - 1;
    }
    if (_shuffle) _remapShuffleOrder(removed);
    notifyListeners();
  }

  Future<int> removeMissingFiles({void Function()? onCurrentRemoved}) async {
    if (_items.isEmpty || _disposed) return 0;
    final checkedPaths = _items
        .where((source) => source.isFile)
        .map((source) => source.value)
        .toSet();
    if (checkedPaths.isEmpty) return 0;
    final pathsToCheck = checkedPaths.toList(growable: false);
    final existingPaths = await PathProbe.existingFiles(pathsToCheck);
    if (_disposed) return 0;
    final missingPaths = checkedPaths.difference(existingPaths);
    if (missingPaths.isEmpty) return 0;
    final current = this.current;
    final before = _items.length;
    final newIndexOf = <int, int>{};
    for (var i = 0, kept = 0; i < before; i++) {
      final source = _items[i];
      if (source.isFile && missingPaths.contains(source.value)) continue;
      newIndexOf[i] = kept++;
    }
    final currentRemoved = _index >= 0 && !newIndexOf.containsKey(_index);
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
    if (_shuffle) _remapShuffleOrder((i) => newIndexOf[i]);
    notifyListeners();
    if (currentRemoved) onCurrentRemoved?.call();
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

  /// Advances by [delta] in queue order. Returns the new item or null when out
  /// of bounds unless [wrap] is true.
  PlayableSource? advance(int delta, {bool wrap = false}) {
    if (_items.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleOrder.isEmpty) return null;
      var pos = _shufflePos + delta;
      if (wrap) {
        final len = _shuffleOrder.length;
        pos = ((pos % len) + len) % len;
      } else if (pos < 0 || pos >= _shuffleOrder.length) {
        return null;
      }
      _shufflePos = pos;
      _index = _shuffleOrder[pos];
      notifyListeners();
      return _items[_index];
    }
    var ni = _index + delta;
    if (wrap) {
      final len = _items.length;
      ni = ((ni % len) + len) % len;
    } else if (ni < 0 || ni >= _items.length) {
      return null;
    }
    _index = ni;
    notifyListeners();
    return _items[_index];
  }

  int? _peekShuffleIndex(int delta) {
    final pos = _shufflePos + delta;
    if (pos < 0 || pos >= _shuffleOrder.length) return null;
    return _shuffleOrder[pos];
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

  void _remapShuffleOrder(int? Function(int) remap, {int? playNext}) {
    if (!_shuffle || _items.isEmpty || _index < 0) {
      _rebuildShuffleOrder(preserveCurrent: true);
      return;
    }
    final placed = <int>{_index};
    final played = <int>[];
    final upcoming = <int>[];
    for (var k = 0; k < _shuffleOrder.length; k++) {
      final mapped = remap(_shuffleOrder[k]);
      if (mapped == null || mapped < 0 || mapped >= _items.length) continue;
      if (mapped == playNext || !placed.add(mapped)) continue;
      (k < _shufflePos ? played : upcoming).add(mapped);
    }
    final random = Random();
    for (var i = 0; i < _items.length; i++) {
      if (i == playNext || !placed.add(i)) continue;
      upcoming.insert(random.nextInt(upcoming.length + 1), i);
    }
    if (playNext != null && playNext != _index) upcoming.insert(0, playNext);
    _shuffleOrder
      ..clear()
      ..addAll(played)
      ..add(_index)
      ..addAll(upcoming);
    _shufflePos = played.length;
  }
}
