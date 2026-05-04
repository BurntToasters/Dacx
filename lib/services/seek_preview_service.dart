import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Generates thumbnail previews for the seek bar by running a hidden,
/// muted secondary [Player] that we seek to the requested timestamp and
/// screenshot on demand.
class SeekPreviewService {
  SeekPreviewService();

  static const int _quantumMs = 1000;
  static const int _cacheLimit = 192;
  static const Duration _debounce = Duration(milliseconds: 25);
  static const Duration _frameSettleDelay = Duration(milliseconds: 25);
  static const int _prefetchRadius = 1;
  static const int _thumbWidth = 320;

  Player? _player;
  // ignore: unused_field
  VideoController? _controller; // Keep alive
  String? _loadedPath;
  bool _enabled = false;
  bool _disposed = false;
  bool _tuned = false;

  final _LruCache<int, Uint8List> _cache = _LruCache(_cacheLimit);

  Timer? _debounceTimer;
  Completer<Uint8List?>? _pendingCompleter;
  int? _pendingKey;
  bool _busy = false;

  final Queue<int> _prefetchQueue = Queue<int>();
  bool _prefetching = false;

  bool get enabled => _enabled;
  bool get isReady => _player != null && _loadedPath != null;
  String? get loadedPath => _loadedPath;

  Future<void> setEnabled(bool value) async {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    if (!value) {
      await _teardown();
    }
  }

  Future<void> setSource(String? path) async {
    if (_disposed) return;
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _teardown();
      return;
    }
    if (!_enabled) {
      _loadedPath = null;
      return;
    }
    if (_loadedPath == normalized && _player != null) return;
    _cache.clear();
    _prefetchQueue.clear();
    await _ensurePlayer();
    final p = _player;
    if (p == null) return;
    try {
      await p.open(Media(normalized), play: false);
      try {
        await p.setVolume(0);
      } catch (_) {}
      _loadedPath = normalized;
    } catch (_) {
      _loadedPath = null;
    }
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final player = Player();
    final controller = VideoController(player);
    _player = player;
    _controller = controller;
    try {
      await player.setVolume(0);
    } catch (_) {}
    await _applyTuning(player);
  }

  Future<void> _applyTuning(Player player) async {
    if (_tuned) return;
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    Future<void> trySet(String name, String value) async {
      try {
        await platform.setProperty(name, value);
      } catch (_) {}
    }

    await trySet('audio', 'no');
    await trySet('ao', 'null');
    await trySet('sid', 'no');
    await trySet('hr-seek', 'yes');
    await trySet('hr-seek-framedrop', 'yes');
    await trySet('vd-lavc-skiploopfilter', 'all');
    await trySet('vd-lavc-fast', 'yes');
    await trySet('vf', 'scale=$_thumbWidth:-2');
    await trySet('cache', 'no');
    await trySet('hwdec', 'auto-safe');
    _tuned = true;
  }

  /// Schedules a screenshot request for [target]. Returns the JPEG bytes.
  Future<Uint8List?> requestPreview(Duration target) {
    if (_disposed || !_enabled || _player == null || _loadedPath == null) {
      return Future.value(null);
    }
    final key = _quantize(target.inMilliseconds);
    final cached = _cache.get(key);
    if (cached != null) {
      _scheduleNeighborPrefetch(key);
      return Future.value(cached);
    }

    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingKey = key;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounce, _runPending);
      return _pendingCompleter!.future;
    }

    final completer = Completer<Uint8List?>();
    _pendingCompleter = completer;
    _pendingKey = key;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _runPending);
    return completer.future;
  }

  int _quantize(int ms) => (ms ~/ _quantumMs) * _quantumMs;

  Future<void> _runPending() async {
    if (_busy) return;
    final key = _pendingKey;
    final completer = _pendingCompleter;
    if (key == null || completer == null) return;
    _busy = true;
    try {
      final cached = _cache.get(key);
      if (cached != null) {
        if (!completer.isCompleted) completer.complete(cached);
        _pendingCompleter = null;
        _pendingKey = null;
        _scheduleNeighborPrefetch(key);
        return;
      }
      final bytes = await _captureAt(key);
      if (!completer.isCompleted) completer.complete(bytes);
      _pendingCompleter = null;
      _pendingKey = null;
      if (bytes != null) _scheduleNeighborPrefetch(key);
    } finally {
      _busy = false;
      if (_pendingCompleter != null && !(_debounceTimer?.isActive ?? false)) {
        unawaited(Future.microtask(_runPending));
      } else {
        unawaited(_drainPrefetch());
      }
    }
  }

  Future<Uint8List?> _captureAt(int key) async {
    final p = _player;
    if (p == null || _loadedPath == null) return null;
    try {
      await p.seek(Duration(milliseconds: key));
    } catch (_) {}
    await Future<void>.delayed(_frameSettleDelay);
    Uint8List? bytes;
    try {
      bytes = await p.screenshot(format: 'image/jpeg');
    } catch (_) {
      bytes = null;
    }
    if (bytes != null) _cache.put(key, bytes);
    return bytes;
  }

  void _scheduleNeighborPrefetch(int aroundKey) {
    if (_disposed || !_enabled) return;
    for (int i = 1; i <= _prefetchRadius; i++) {
      final ahead = aroundKey + i * _quantumMs;
      final behind = aroundKey - i * _quantumMs;
      if (ahead >= 0 &&
          _cache.get(ahead) == null &&
          !_prefetchQueue.contains(ahead)) {
        _prefetchQueue.add(ahead);
      }
      if (behind >= 0 &&
          _cache.get(behind) == null &&
          !_prefetchQueue.contains(behind)) {
        _prefetchQueue.add(behind);
      }
    }
    unawaited(_drainPrefetch());
  }

  Future<void> _drainPrefetch() async {
    if (_prefetching || _busy) return;
    if (_prefetchQueue.isEmpty) return;
    _prefetching = true;
    try {
      while (!_disposed &&
          _enabled &&
          !_busy &&
          _prefetchQueue.isNotEmpty &&
          _pendingCompleter == null) {
        final key = _prefetchQueue.removeFirst();
        if (_cache.get(key) != null) continue;
        await _captureAt(key);
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _prefetching = false;
    }
  }

  Future<void> _teardown() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
    }
    _pendingCompleter = null;
    _pendingKey = null;
    _prefetchQueue.clear();
    _cache.clear();
    final p = _player;
    _controller = null;
    _player = null;
    _loadedPath = null;
    _tuned = false;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
  }
}

class _LruCache<K, V> {
  _LruCache(this.capacity);
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  V? get(K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}
