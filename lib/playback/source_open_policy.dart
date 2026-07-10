/// Pure open/autoplay rules extracted from [PlayerScreen].
abstract final class SourceOpenPolicy {
  static bool shouldAutoplayOnOpen({
    required bool forcePlay,
    required bool autoPlaySetting,
  }) {
    return forcePlay || autoPlaySetting;
  }

  static bool shouldForcePlaySameFile({
    required bool forcePlay,
    required bool isPlaying,
  }) {
    return forcePlay && !isPlaying;
  }
}
