/// Limits how often native media-session position updates are sent.
class MediaSessionPositionThrottle {
  MediaSessionPositionThrottle({
    this.minInterval = const Duration(milliseconds: 400),
  });

  final Duration minInterval;
  DateTime? _lastSent;

  /// Returns true when a position update should be forwarded now.
  bool shouldSend(DateTime now) {
    final last = _lastSent;
    if (last != null && now.difference(last) < minInterval) {
      return false;
    }
    _lastSent = now;
    return true;
  }

  void reset() => _lastSent = null;
}
