/// Pure cyclic track-selection rules extracted from [PlayerScreen].
abstract final class TrackCyclePolicy {
  static bool canCycle({required int selectableCount}) => selectableCount > 1;

  static int nextIndex({required int currentIndex, required int listLength}) {
    if (listLength <= 0) return 0;
    if (currentIndex < 0) return 0;
    return (currentIndex + 1) % listLength;
  }
}
