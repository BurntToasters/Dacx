/// Persisted state used by the opt-in advanced playback tools.
///
/// These models intentionally contain no Flutter or mpv types. This keeps the
/// persistence boundary small and makes malformed preference data fail closed.
class PlaybackAdjustment {
  const PlaybackAdjustment({this.audioMs = 0, this.subtitleMs = 0});

  final int audioMs;
  final int subtitleMs;

  bool get isDefault => audioMs == 0 && subtitleMs == 0;
}

class PlaybackMarker {
  const PlaybackMarker({
    required this.id,
    required this.positionMs,
    required this.label,
  });

  final String id;
  final int positionMs;
  final String label;

  PlaybackMarker copyWith({String? label, int? positionMs}) => PlaybackMarker(
    id: id,
    positionMs: positionMs ?? this.positionMs,
    label: label ?? this.label,
  );
}
