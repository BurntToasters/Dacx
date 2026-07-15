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
