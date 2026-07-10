import '../models/playable_source.dart';
import 'player_path_utils.dart';

/// Pre-open validation outcome for [PlayerScreen._loadSourceInternal].
enum SourceLoadValidationFailure { none, emptySource, invalidUrl, missingFile }

/// User-visible message kind for load validation / open failures.
enum SourceLoadUserMessageKind {
  invalidFilePath,
  invalidStreamUrl,
  fileNotFound,
  permissionDenied,
  openFailed,
}

class SourceLoadValidationResult {
  const SourceLoadValidationResult(this.failure);

  final SourceLoadValidationFailure failure;

  bool get isOk => failure == SourceLoadValidationFailure.none;
}

class SourceLoadValidationReaction {
  const SourceLoadValidationReaction({
    required this.logEvent,
    required this.shouldPruneRecentFiles,
    required this.userMessage,
  });

  final String logEvent;
  final bool shouldPruneRecentFiles;
  final SourceLoadUserMessageKind? userMessage;
}

/// Pure pre-load validation rules extracted from [PlayerScreen].
abstract final class SourceLoadValidationPolicy {
  static SourceLoadValidationReaction reactionFor(
    SourceLoadValidationFailure failure,
  ) {
    return switch (failure) {
      SourceLoadValidationFailure.none => const SourceLoadValidationReaction(
        logEvent: '',
        shouldPruneRecentFiles: false,
        userMessage: null,
      ),
      SourceLoadValidationFailure.emptySource =>
        const SourceLoadValidationReaction(
          logEvent: 'media_load_invalid_source',
          shouldPruneRecentFiles: false,
          userMessage: SourceLoadUserMessageKind.invalidFilePath,
        ),
      SourceLoadValidationFailure.invalidUrl =>
        const SourceLoadValidationReaction(
          logEvent: 'url_load_invalid',
          shouldPruneRecentFiles: false,
          userMessage: SourceLoadUserMessageKind.invalidStreamUrl,
        ),
      SourceLoadValidationFailure.missingFile =>
        const SourceLoadValidationReaction(
          logEvent: 'file_load_missing',
          shouldPruneRecentFiles: true,
          userMessage: SourceLoadUserMessageKind.fileNotFound,
        ),
    };
  }

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

  /// Runs request validation, then normalized file existence checks.
  static SourceLoadValidationResult validateNormalizedOpen({
    required PlayableSource source,
    required String trimmedValue,
    required PlayableSource normalizedSource,
    required bool fileExists,
  }) {
    final request = validateRequest(source: source, trimmedValue: trimmedValue);
    if (!request.isOk) return request;
    return validateNormalizedFile(
      isFile: normalizedSource.isFile,
      fileExists: fileExists,
    );
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

  static SourceLoadUserMessageKind userMessage(SourceLoadFailureKind kind) =>
      switch (kind) {
        SourceLoadFailureKind.permissionDenied =>
          SourceLoadUserMessageKind.permissionDenied,
        SourceLoadFailureKind.generic => SourceLoadUserMessageKind.openFailed,
      };
}
