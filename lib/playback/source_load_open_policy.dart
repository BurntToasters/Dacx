import 'player_path_utils.dart';
import 'source_load_validation_policy.dart';

/// UI/logging reaction after [IPlayerService.open] fails.
class SourceLoadOpenFailureReaction {
  const SourceLoadOpenFailureReaction({
    required this.shouldUpdateUi,
    required this.logAsWarning,
  });

  final bool shouldUpdateUi;
  final bool logAsWarning;
}

/// Pure open-phase rules extracted from [PlayerScreen._loadSourceInternal].
abstract final class SourceLoadOpenPolicy {
  static bool shouldWarnUnrecognizedExtension({
    required bool isFile,
    required String ext,
  }) {
    return isFile &&
        ext.isNotEmpty &&
        !PlayerPathUtils.isSupportedExtension(ext);
  }

  static SourceLoadOpenFailureReaction openFailureReaction({
    required SourceLoadFailureKind kind,
    required bool isLoadCurrent,
    required bool mounted,
  }) {
    return SourceLoadOpenFailureReaction(
      shouldUpdateUi: isLoadCurrent && mounted,
      logAsWarning: kind == SourceLoadFailureKind.permissionDenied,
    );
  }
}
