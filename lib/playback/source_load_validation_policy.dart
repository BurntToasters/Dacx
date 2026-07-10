import '../models/playable_source.dart';
import 'player_path_utils.dart';

/// Pre-open validation outcome for [PlayerScreen._loadSourceInternal].
enum SourceLoadValidationFailure { none, emptySource, invalidUrl, missingFile }

class SourceLoadValidationResult {
  const SourceLoadValidationResult(this.failure);

  final SourceLoadValidationFailure failure;

  bool get isOk => failure == SourceLoadValidationFailure.none;
}

/// Pure pre-load validation rules extracted from [PlayerScreen].
abstract final class SourceLoadValidationPolicy {
  static SourceLoadValidationResult validateRequest({
    required PlayableSource source,
    required String trimmedValue,
  }) {
    if (trimmedValue.isEmpty) {
      return const SourceLoadValidationResult(
        SourceLoadValidationFailure.emptySource,
      );
    }
    if (source.isUrl && !PlayableSource.isSupportedUrl(trimmedValue)) {
      return const SourceLoadValidationResult(
        SourceLoadValidationFailure.invalidUrl,
      );
    }
    return const SourceLoadValidationResult(SourceLoadValidationFailure.none);
  }

  static SourceLoadValidationResult validateNormalizedFile({
    required bool isFile,
    required bool fileExists,
  }) {
    if (isFile && !fileExists) {
      return const SourceLoadValidationResult(
        SourceLoadValidationFailure.missingFile,
      );
    }
    return const SourceLoadValidationResult(SourceLoadValidationFailure.none);
  }
}

/// Open failure classification for snackbar and logging.
enum SourceLoadFailureKind { permissionDenied, generic }

/// Pure open-error rules extracted from [PlayerScreen._loadSourceInternal].
abstract final class SourceLoadFailurePolicy {
  static SourceLoadFailureKind classify(Object error) {
    return PlayerPathUtils.isPermissionDeniedError(error)
        ? SourceLoadFailureKind.permissionDenied
        : SourceLoadFailureKind.generic;
  }

  static String logEvent(SourceLoadFailureKind kind) => switch (kind) {
    SourceLoadFailureKind.permissionDenied => 'file_load_permission_denied',
    SourceLoadFailureKind.generic => 'file_load_failed',
  };
}
