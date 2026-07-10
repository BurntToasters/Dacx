import 'player_path_utils.dart';

/// Normalized drag-and-drop path batch.
class DropPathBatch {
  const DropPathBatch({required this.paths, required this.skippedCount});

  final List<String> paths;
  final int skippedCount;

  bool get isEmpty => paths.isEmpty;
}

/// Pure drag-drop path normalization extracted from [PlayerScreen._onDragDone].
abstract final class DropPathBatchPolicy {
  static DropPathBatch fromRawPaths({
    required Iterable<String> rawPaths,
    required bool windows,
  }) {
    final raw = rawPaths.toList(growable: false);
    final paths = raw
        .map(
          (path) => PlayerPathUtils.normalizeDropPath(path, windows: windows),
        )
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    return DropPathBatch(paths: paths, skippedCount: raw.length - paths.length);
  }
}
