import '../services/settings_service.dart';

/// Pure playlist navigation rules extracted from [PlayerScreen._advancePlaylist].
abstract final class PlaylistAdvancePolicy {
  static bool shouldWrapQueue(LoopMode mode) => mode == LoopMode.loop;

  /// Single-item repeat is handled by libmpv; queue should not auto-advance.
  static bool shouldAdvanceOnCompleted(LoopMode mode) =>
      mode != LoopMode.single;
}
