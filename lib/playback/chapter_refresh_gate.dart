/// Skips redundant mpv chapter-list property reads when file/count unchanged.
class ChapterRefreshGate {
  String? _path;
  int? _count;

  void invalidate() {
    _path = null;
    _count = null;
  }

  /// Returns true when chapter metadata should be re-fetched.
  bool shouldRefresh({required String? path, required int chapterCount}) {
    if (path == _path && chapterCount == _count) {
      return false;
    }
    _path = path;
    _count = chapterCount;
    return true;
  }
}
