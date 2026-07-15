/// Pure chapter-step rules extracted from [PlayerScreen._stepChapter].
abstract final class ChapterNavigationPolicy {
  static int stepIndex({
    required int currentIndex,
    required int delta,
    required int chapterCount,
  }) {
    if (chapterCount <= 0) return 0;
    return (currentIndex + delta).clamp(0, chapterCount - 1);
  }
}
