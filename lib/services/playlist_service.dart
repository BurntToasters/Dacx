import 'dart:math';

import 'package:flutter/foundation.dart';

/// In-memory playback queue. Persistence is intentionally omitted: queue lives
/// for the session. The `index` is `-1` when the queue is empty.
class PlaylistService extends ChangeNotifier {
  final List<String> _items = [];
  int _index = -1;
  bool _shuffle = false;
  final List<int> _shuffleOrder = [];
  int _shufflePos = -1;

  List<String> get items => List.unmodifiable(_items);
  int get index => _index;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  String? get current => (_index >= 0 && _index < _items.length)
      ? _items[_index]
      : null;
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
  void replace(List<String> paths, {int startIndex = 0}) {
    _items
      ..clear()
      ..addAll(paths.where((p) => p.trim().isNotEmpty));
    if (_items.isEmpty) {
      _index = -1;
    } else {
      _index = startIndex.clamp(0, _items.length - 1);
    }
    _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
  }

  /// Appends [paths] to the queue.
  void addAll(List<String> paths) {
    final filtered = paths.where((p) => p.trim().isNotEmpty).toList();
    if (filtered.isEmpty) return;
    final wasEmpty = _items.isEmpty;
    _items.addAll(filtered);
    if (wasEmpty) _index = 0;
    _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
  }

  /// Inserts [path] right after the current item.
  void playNext(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    if (_items.isEmpty) {
      _items.add(trimmed);
      _index = 0;
    } else {
      _items.insert(_index + 1, trimmed);
    }
    _rebuildShuffleOrder(preserveCurrent: true);
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
    _rebuildShuffleOrder(preserveCurrent: true);
    notifyListeners();
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
  String? advance(int delta) {
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

  String? _peekRelative(int delta) {
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
    if (preserveCurrent && _index >= 0) {
      indices.remove(_index);
      indices.insert(0, _index);
    }
    _shuffleOrder
      ..clear()
      ..addAll(indices);
    _shufflePos = preserveCurrent ? 0 : -1;
  }
}
