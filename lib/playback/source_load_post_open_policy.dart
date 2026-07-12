import '../models/playable_source.dart';
import 'load_outcome_policy.dart';
import 'source_load_policy.dart';

/// Post-open side-effect plan for [_loadSourceInternal].
class SourceLoadPostOpenPlan {
  const SourceLoadPostOpenPlan({
    required this.shouldProceed,
    required this.shouldRefreshUi,
    required this.seekPreviewPath,
    required this.shouldPersistRecent,
    required this.shouldRememberOpenDirectory,
    required this.resumeTrackingPath,
    required this.shouldApplyResume,
    required this.recentPersistLogEvent,
  });

  final bool shouldProceed;
  final bool shouldRefreshUi;
  final String? seekPreviewPath;
  final bool shouldPersistRecent;
  final bool shouldRememberOpenDirectory;
  final String? resumeTrackingPath;
  final bool shouldApplyResume;
  final String recentPersistLogEvent;
}

/// Post-open follow-up work scheduled by the screen after a successful open.
class SourceLoadPostOpenFollowUp {
  const SourceLoadPostOpenFollowUp({
    required this.shouldCacheTracks,
    required this.shouldApplyAudioFilters,
    required this.shouldRefreshChapters,
    required this.shouldApplyMultiAudioMix,
    required this.shouldUpdateMediaSessionMetadata,
    required this.seekPreviewPath,
    required this.shouldClearSeekPreview,
    required this.resumeTrackingPath,
    required this.shouldApplyResume,
    required this.shouldRefreshUi,
    required this.shouldPersistRecent,
    required this.shouldRememberOpenDirectory,
    required this.recentPersistLogEvent,
  });

  final bool shouldCacheTracks;
  final bool shouldApplyAudioFilters;
  final bool shouldRefreshChapters;
  final bool shouldApplyMultiAudioMix;
  final bool shouldUpdateMediaSessionMetadata;
  final String? seekPreviewPath;
  final bool shouldClearSeekPreview;
  final String? resumeTrackingPath;
  final bool shouldApplyResume;
  final bool shouldRefreshUi;
  final bool shouldPersistRecent;
  final bool shouldRememberOpenDirectory;
  final String recentPersistLogEvent;

  static const SourceLoadPostOpenFollowUp noop = SourceLoadPostOpenFollowUp(
    shouldCacheTracks: false,
    shouldApplyAudioFilters: false,
    shouldRefreshChapters: false,
    shouldApplyMultiAudioMix: false,
    shouldUpdateMediaSessionMetadata: false,
    seekPreviewPath: null,
    shouldClearSeekPreview: false,
    resumeTrackingPath: null,
    shouldApplyResume: false,
    shouldRefreshUi: false,
    shouldPersistRecent: false,
    shouldRememberOpenDirectory: false,
    recentPersistLogEvent: '',
  );
}

/// Bundles post-open decisions after a successful [IPlayerService.open].
abstract final class SourceLoadPostOpenPolicy {
  static SourceLoadPostOpenPlan plan({
    required bool isLoadCurrent,
    required bool isDisposed,
    required bool mounted,
    required PlayableSource normalizedSource,
    required bool isAudioFile,
  }) {
    final shouldProceed = LoadOutcomePolicy.shouldProceedAfterOpen(
      isLoadCurrent: isLoadCurrent,
      isDisposed: isDisposed,
    );
    if (!shouldProceed) {
      return const SourceLoadPostOpenPlan(
        shouldProceed: false,
        shouldRefreshUi: false,
        seekPreviewPath: null,
        shouldPersistRecent: false,
        shouldRememberOpenDirectory: false,
        resumeTrackingPath: null,
        shouldApplyResume: false,
        recentPersistLogEvent: '',
      );
    }

    return SourceLoadPostOpenPlan(
      shouldProceed: true,
      shouldRefreshUi: LoadOutcomePolicy.shouldRefreshUi(
        mounted: mounted,
        isDisposed: isDisposed,
        isLoadCurrent: isLoadCurrent,
      ),
      seekPreviewPath: SourceLoadPolicy.seekPreviewFilePath(
        source: normalizedSource,
        isAudioFile: isAudioFile,
      ),
      shouldPersistRecent: SourceLoadPolicy.shouldPersistToRecents(
        normalizedSource,
      ),
      shouldRememberOpenDirectory: SourceLoadPolicy.shouldRememberOpenDirectory(
        normalizedSource,
      ),
      resumeTrackingPath: SourceLoadPolicy.resumeTrackingPath(normalizedSource),
      shouldApplyResume: SourceLoadPolicy.shouldApplyResume(normalizedSource),
      recentPersistLogEvent: SourceLoadPolicy.recentPersistLogEvent(
        normalizedSource,
      ),
    );
  }

  static SourceLoadPostOpenFollowUp followUpFor(SourceLoadPostOpenPlan plan) {
    if (!plan.shouldProceed) return SourceLoadPostOpenFollowUp.noop;
    return SourceLoadPostOpenFollowUp(
      shouldCacheTracks: true,
      shouldApplyAudioFilters: true,
      shouldRefreshChapters: true,
      shouldApplyMultiAudioMix: true,
      shouldUpdateMediaSessionMetadata: true,
      seekPreviewPath: plan.seekPreviewPath,
      shouldClearSeekPreview: plan.seekPreviewPath == null,
      resumeTrackingPath: plan.resumeTrackingPath,
      shouldApplyResume: plan.shouldApplyResume,
      shouldRefreshUi: plan.shouldRefreshUi,
      shouldPersistRecent: plan.shouldPersistRecent,
      shouldRememberOpenDirectory: plan.shouldRememberOpenDirectory,
      recentPersistLogEvent: plan.recentPersistLogEvent,
    );
  }
}
