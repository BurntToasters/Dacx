import '../services/settings_service.dart';

/// What [_persistResumePosition] should do for the current playback position.
enum ResumePersistAction { skip, clear, save }

/// What [_maybeApplyResume] should do once duration is known (or polling ends).
enum ResumeApplyAction { skip, waitForDuration, clearStored, seek }

/// Pure resume-position rules extracted from [PlayerScreen].
abstract final class ResumePlaybackPolicy {
  static const int durationPollAttempts = 20;

  static ResumeApplyAction applyAction({
    required int? resumeMs,
    required int durationMs,
    int tailIgnoreSeconds = SettingsService.resumeTailIgnoreSeconds,
  }) {
    if (resumeMs == null || resumeMs <= 0) return ResumeApplyAction.skip;
    if (durationMs <= 0) return ResumeApplyAction.waitForDuration;
    if (shouldClearNearEndResume(
      resumeMs: resumeMs,
      durationMs: durationMs,
      tailIgnoreSeconds: tailIgnoreSeconds,
    )) {
      return ResumeApplyAction.clearStored;
    }
    return ResumeApplyAction.seek;
  }

  static ResumePersistAction persistAction({
    required Duration position,
    required Duration duration,
    int minElapsedSeconds = SettingsService.resumeMinElapsedSeconds,
    int tailIgnoreSeconds = SettingsService.resumeTailIgnoreSeconds,
  }) {
    if (position.inSeconds < minElapsedSeconds) {
      return ResumePersistAction.skip;
    }
    if (duration.inSeconds > 0 &&
        (duration - position).inSeconds < tailIgnoreSeconds) {
      return ResumePersistAction.clear;
    }
    return ResumePersistAction.save;
  }

  /// Whether a saved resume is too close to the end to apply.
  static bool shouldClearNearEndResume({
    required int resumeMs,
    required int durationMs,
    int tailIgnoreSeconds = SettingsService.resumeTailIgnoreSeconds,
  }) {
    return durationMs > 0 && resumeMs >= durationMs - tailIgnoreSeconds * 1000;
  }

  /// Formats a duration for the resume OSD (`m:ss` or `h:mm:ss`).
  static String formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes.remainder(60)}:$s';
  }
}
