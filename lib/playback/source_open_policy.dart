/// Pure open/autoplay rules extracted from [PlayerScreen].
class SourceOpenParams {
  const SourceOpenParams({required this.path, required this.play});

  final String path;
  final bool play;
}

abstract final class SourceOpenPolicy {
  static SourceOpenParams paramsFor({
    required String normalizedPath,
    required bool forcePlay,
    required bool autoPlaySetting,
    bool? playOverride,
  }) {
    return SourceOpenParams(
      path: normalizedPath,
      play: shouldAutoplayOnOpen(
        forcePlay: forcePlay,
        autoPlaySetting: autoPlaySetting,
        playOverride: playOverride,
      ),
    );
  }

  /// [playOverride] wins when set (generic open override).
  /// Otherwise [forcePlay] or the autoplay setting decide.
  static bool shouldAutoplayOnOpen({
    required bool forcePlay,
    required bool autoPlaySetting,
    bool? playOverride,
  }) {
    if (playOverride != null) return playOverride;
    return forcePlay || autoPlaySetting;
  }

  /// When Open With / second-instance requests the same path again:
  /// - if paused → resume
  /// - if already playing → reload from the start (restart)
  static bool shouldResumeSameFile({
    required bool forcePlay,
    required bool isPlaying,
  }) {
    return forcePlay && !isPlaying;
  }

  static bool shouldRestartSameFile({
    required bool forcePlay,
    required bool isPlaying,
  }) {
    return forcePlay && isPlaying;
  }
}
