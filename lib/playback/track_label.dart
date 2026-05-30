/// Formats mpv track metadata for OSD / menu labels.
String formatTrackLabel({
  String? title,
  String? language,
  required String fallbackId,
}) {
  final parts = <String>[];
  if (title != null && title.trim().isNotEmpty) parts.add(title.trim());
  if (language != null && language.trim().isNotEmpty) {
    parts.add(language.trim());
  }
  if (parts.isEmpty) return 'Track $fallbackId';
  return parts.join(' · ');
}
