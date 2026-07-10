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
  }) {
    return SourceOpenParams(
      path: normalizedPath,
      play: shouldAutoplayOnOpen(
        forcePlay: forcePlay,
        autoPlaySetting: autoPlaySetting,
      ),
    );
  }

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
