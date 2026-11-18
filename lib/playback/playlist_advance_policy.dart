import '../services/settings_service.dart';

/// Pure playlist navigation rules extracted from [PlayerScreen._advancePlaylist].
abstract final class PlaylistAdvancePolicy {
  static bool shouldWrapQueue(LoopMode mode) => mode == LoopMode.loop;

  /// Single-item repeat is handled by libmpv; queue should not auto-advance.
  static bool shouldAdvanceOnCompleted(LoopMode mode) =>
      mode != LoopMode.single;

  static bool canGoNext({
    required int queueLength,
    required LoopMode loopMode,
    required bool hasNextInOrder,
  }) => queueLength > 0 && (shouldWrapQueue(loopMode) || hasNextInOrder);

  static bool canGoPrevious({
    required int queueLength,
    required LoopMode loopMode,
    required bool hasPreviousInOrder,
  }) => queueLength > 0 && (shouldWrapQueue(loopMode) || hasPreviousInOrder);
}
