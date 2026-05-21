import 'load_queue.dart';
import 'chapter_refresh_gate.dart';
import 'media_session_throttle.dart';

/// Coordinates serialized loads, load-generation tokens, and hot-path throttles
/// extracted from [PlayerScreen] for testability.
class PlaybackController {
  PlaybackController({
    LoadQueue? loadQueue,
    ChapterRefreshGate? chapterGate,
    MediaSessionPositionThrottle? mediaSessionThrottle,
  }) : loadQueue = loadQueue ?? LoadQueue(),
       chapterGate = chapterGate ?? ChapterRefreshGate(),
       mediaSessionThrottle =
           mediaSessionThrottle ?? MediaSessionPositionThrottle();

  final LoadQueue loadQueue;
  final ChapterRefreshGate chapterGate;
  final MediaSessionPositionThrottle mediaSessionThrottle;

  int _loadGeneration = 0;

  int get loadGeneration => _loadGeneration;

  /// Allocates a new load generation; returns the token for this open attempt.
  int beginLoad() => ++_loadGeneration;

  bool isLoadCurrent(int generation) =>
      !_disposed && generation == _loadGeneration;

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    mediaSessionThrottle.reset();
    chapterGate.invalidate();
  }
}
