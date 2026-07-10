/// Result of evaluating a post-update launch marker.
enum UpdateLaunchNoticeKind { none, success, failed }

class UpdateLaunchNoticeDecision {
  const UpdateLaunchNoticeDecision._(this.kind, this.targetVersion);

  const UpdateLaunchNoticeDecision.none()
    : this._(UpdateLaunchNoticeKind.none, null);

  const UpdateLaunchNoticeDecision.success(String version)
    : this._(UpdateLaunchNoticeKind.success, version);

  const UpdateLaunchNoticeDecision.failed(String version)
    : this._(UpdateLaunchNoticeKind.failed, version);

  final UpdateLaunchNoticeKind kind;
  final String? targetVersion;

  bool get shouldShow => kind != UpdateLaunchNoticeKind.none;
}

/// Pure logic for the post-update snackbar shown on next launch.
abstract final class UpdateLaunchPolicy {
  static const Duration defaultMaxAge = Duration(days: 7);

  static UpdateLaunchNoticeDecision decide({
    required Map<String, Object?>? marker,
    required int nowEpochMs,
    required String actualVersion,
    Duration maxAge = defaultMaxAge,
  }) {
    if (marker == null) return const UpdateLaunchNoticeDecision.none();
    final targetVersion = marker['target_version'] as String?;
    if (targetVersion == null) return const UpdateLaunchNoticeDecision.none();

    final startedAt = marker['started_at_ms'] as int?;
    if (startedAt != null) {
      final ageMs = nowEpochMs - startedAt;
      if (ageMs > maxAge.inMilliseconds) {
        return const UpdateLaunchNoticeDecision.none();
      }
    }

    if (actualVersion == targetVersion) {
      return UpdateLaunchNoticeDecision.success(targetVersion);
    }
    return UpdateLaunchNoticeDecision.failed(targetVersion);
  }
}
