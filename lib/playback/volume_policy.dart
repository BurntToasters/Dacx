final class ScrollVolumeAccumulator {
  ScrollVolumeAccumulator({
    this.notchPixels = 50.0,
    this.idleReset = const Duration(milliseconds: 200),
    this.step = 5.0,
  });

  final double notchPixels;
  final Duration idleReset;
  final double step;

  double _accumulated = 0;
  Duration? _lastEvent;

  double add(double scrollDeltaY, Duration timestamp) {
    if (scrollDeltaY == 0 || scrollDeltaY.isNaN) return 0;
    final last = _lastEvent;
    if (last != null && timestamp - last >= idleReset) {
      _accumulated = 0;
    }
    if (_accumulated != 0 && (_accumulated < 0) != (scrollDeltaY < 0)) {
      _accumulated = 0;
    }
    _lastEvent = timestamp;
    _accumulated += scrollDeltaY;
    if (_accumulated.abs() < notchPixels) return 0;
    final up = _accumulated < 0;
    _accumulated = 0;
    return up ? step : -step;
  }

  void reset() {
    _accumulated = 0;
    _lastEvent = null;
  }
}

/// Result of a mute toggle decision.
class MuteToggleResult {
  const MuteToggleResult({
    required this.newVolume,
    required this.volumeBeforeMute,
  });

  final double newVolume;
  final double volumeBeforeMute;
}

/// Pure volume rules extracted from [PlayerScreen].
abstract final class VolumePolicy {
  static double clampVolume(double volume) => volume.clamp(0.0, 100.0);

  static double adjustVolume({required double current, required double delta}) {
    return clampVolume(current + delta);
  }

  static MuteToggleResult toggleMute({
    required double currentVolume,
    required double volumeBeforeMute,
  }) {
    if (currentVolume > 0) {
      return MuteToggleResult(newVolume: 0, volumeBeforeMute: currentVolume);
    }
    return MuteToggleResult(
      newVolume: volumeBeforeMute,
      volumeBeforeMute: volumeBeforeMute,
    );
  }
}
