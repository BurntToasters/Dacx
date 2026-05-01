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

  static const int _quantumMs = 2000;
  static const int _cacheLimit = 24;
  static const Duration _debounce = Duration(milliseconds: 90);
  static const Duration _frameSettleDelay = Duration(milliseconds: 80);

  Player? _player;
  // ignore: unused_field
  VideoController? _controller; // Keep alive
  String? _loadedPath;
  bool _enabled = false;
  bool _disposed = false;

  final _LruCache<int, Uint8List> _cache = _LruCache(_cacheLimit);

  Timer? _debounceTimer;
  Completer<Uint8List?>? _pendingCompleter;
  int? _pendingKey;
  bool _busy = false;

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
  }

  /// Schedules a screenshot request for [target]. Returns the JPEG bytes
  Future<Uint8List?> requestPreview(Duration target) {
    if (_disposed || !_enabled || _player == null || _loadedPath == null) {
      return Future.value(null);
    }
    final key = (target.inMilliseconds ~/ _quantumMs) * _quantumMs;
    final cached = _cache.get(key);
    if (cached != null) return Future.value(cached);

    _debounceTimer?.cancel();
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
    }
    final completer = Completer<Uint8List?>();
    _pendingCompleter = completer;
    _pendingKey = key;

    _debounceTimer = Timer(_debounce, _runPending);
    return completer.future;
  }

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
        return;
      }
      final p = _player;
      if (p == null || _loadedPath == null) {
        if (!completer.isCompleted) completer.complete(null);
        _pendingCompleter = null;
        _pendingKey = null;
        return;
      }
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
      if (!completer.isCompleted) completer.complete(bytes);
      _pendingCompleter = null;
      _pendingKey = null;
    } finally {
      _busy = false;
      // Drain a request that arrived while we were working.
      if (_pendingCompleter != null && !(_debounceTimer?.isActive ?? false)) {
        unawaited(Future.microtask(_runPending));
      }
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
    _cache.clear();
    final p = _player;
    _controller = null;
    _player = null;
    _loadedPath = null;
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
