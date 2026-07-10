import '../models/playable_source.dart';

/// Pure post-open rules extracted from [PlayerScreen._loadSourceInternal].
abstract final class SourceLoadPolicy {
  static bool shouldPersistToRecents(PlayableSource source) {
    return source.isFile || PlayableSource.isDisplaySafeUrl(source.value);
  }

  static String? seekPreviewFilePath({
    required PlayableSource source,
    required bool isAudioFile,
  }) {
    if (!source.isFile || isAudioFile) return null;
    return source.value;
  }

  static String? resumeTrackingPath(PlayableSource source) {
    return source.isFile ? source.value : null;
  }

  static bool shouldApplyResume(PlayableSource source) => source.isFile;

  static bool shouldRememberOpenDirectory(PlayableSource source) =>
      source.isFile;

  static String recentPersistLogEvent(PlayableSource source) {
    return shouldPersistToRecents(source)
        ? 'recent_file_added'
        : 'recent_url_skipped';
  }
}
