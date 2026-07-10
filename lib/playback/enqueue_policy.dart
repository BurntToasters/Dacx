/// How new sources should join the playback queue.
enum EnqueueMode { replaceAndPlay, append }

/// Pure queue rules extracted from [PlayerScreen._enqueueSources].
abstract final class EnqueuePolicy {
  static EnqueueMode mode({
    required bool playNow,
    required bool playlistEmpty,
  }) {
    if (playNow || playlistEmpty) return EnqueueMode.replaceAndPlay;
    return EnqueueMode.append;
  }
}

/// What drag-and-drop should do after paths are normalized.
enum DropFileAction { none, loadSingle, enqueuePlayNow }

/// Pure drag-drop playback rules extracted from [PlayerScreen._onDragDone].
abstract final class DropFilePolicy {
  static DropFileAction action({required int validPathCount}) {
    if (validPathCount <= 0) return DropFileAction.none;
    if (validPathCount == 1) return DropFileAction.loadSingle;
    return DropFileAction.enqueuePlayNow;
  }
}
