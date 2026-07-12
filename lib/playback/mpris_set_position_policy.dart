/// Pure MPRIS SetPosition track-id matching rules.
abstract final class MprisSetPositionPolicy {
  /// Returns true when [requestedTrackId] matches the currently published
  /// [currentTrackId] and the session has an active track (not cleared/`/`).
  static bool shouldSeek({
    required String requestedTrackId,
    required String currentTrackId,
  }) {
    if (currentTrackId.isEmpty || currentTrackId == '/') return false;
    return requestedTrackId == currentTrackId;
  }
}
