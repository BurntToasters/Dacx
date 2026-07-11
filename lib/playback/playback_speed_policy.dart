/// Shared playback-rate presets for Settings, transport, and shortcuts.
abstract final class PlaybackSpeedPolicy {
  static const List<double> presets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Next preset after [current] (wraps). Snaps to nearest preset first.
  static double cycleNext(double current) {
    final i = _nearestIndex(current);
    return presets[(i + 1) % presets.length];
  }

  static double stepSlower(double current) {
    final i = _nearestIndex(current);
    return presets[i <= 0 ? 0 : i - 1];
  }

  static double stepFaster(double current) {
    final i = _nearestIndex(current);
    return presets[i >= presets.length - 1 ? presets.length - 1 : i + 1];
  }

  static String formatLabel(double speed) {
    final nearest = nearestPreset(speed);
    if (nearest == nearest.roundToDouble()) {
      return '${nearest.toInt()}×';
    }
    return '$nearest×';
  }

  static double nearestPreset(double current) => presets[_nearestIndex(current)];

  static int _nearestIndex(double current) {
    var best = 0;
    var bestDelta = (presets[0] - current).abs();
    for (var i = 1; i < presets.length; i++) {
      final delta = (presets[i] - current).abs();
      if (delta < bestDelta) {
        best = i;
        bestDelta = delta;
      }
    }
    return best;
  }
}
