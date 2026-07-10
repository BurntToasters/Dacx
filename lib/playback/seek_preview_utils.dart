/// Pure helpers for [SeekPreviewService] seek-bar thumbnail caching.
abstract final class SeekPreviewUtils {
  static const defaultQuantumMs = 1000;

  /// Rounds [positionMs] down to the nearest [quantumMs] bucket.
  static int quantizeMs(int positionMs, {int quantumMs = defaultQuantumMs}) {
    if (quantumMs <= 0) return positionMs;
    return (positionMs ~/ quantumMs) * quantumMs;
  }
}

/// Small LRU cache used by seek-preview thumbnail generation.
class SeekPreviewLruCache<K, V> {
  SeekPreviewLruCache(this.capacity);

  final int capacity;
  final Map<K, V> _map = <K, V>{};

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();

  int get length => _map.length;
}
