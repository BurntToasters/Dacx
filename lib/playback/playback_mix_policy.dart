/// Builds mpv `lavfi-complex` graphs for experimental multi-audio mix.
abstract final class PlaybackMixPolicy {
  /// Audio-only branch: format each [aidN] track and amix into [ao].
  static String buildAudioMixBranch(List<String> audioIds) {
    final buf = StringBuffer();
    for (var i = 0; i < audioIds.length; i++) {
      buf.write(
        '[aid${audioIds[i]}] '
        'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo '
        '[a${i + 1}] ; ',
      );
    }
    for (var i = 0; i < audioIds.length; i++) {
      buf.write('[a${i + 1}]');
    }
    buf.write(' amix=inputs=${audioIds.length}:normalize=0 [ao]');
    return buf.toString();
  }

  /// Full graph with optional video passthrough label [vidN].
  static String buildLavfiComplex({
    required List<String> audioIds,
    String? videoTrackId,
  }) {
    final audioChain = buildAudioMixBranch(audioIds);
    if (videoTrackId != null && videoTrackId.isNotEmpty) {
      return '[vid$videoTrackId] null [vo] ; $audioChain';
    }
    return audioChain;
  }

  /// Returns only numeric mpv audio track ids suitable for lavfi labels.
  static List<String> numericAudioIds(Iterable<String> raw) => raw
      .where((id) => id != 'auto' && id != 'no')
      .where((id) => int.tryParse(id) != null)
      .toList(growable: false);

  /// Returns only numeric mpv video track ids suitable for lavfi labels.
  static List<String> numericVideoIds(Iterable<String> raw) => raw
      .where((id) => id != 'auto' && id != 'no')
      .where((id) => int.tryParse(id) != null)
      .toList(growable: false);
}

/// Tracks per-load mix cache state so IDs from one file cannot leak into the
/// next file's lavfi graph.
final class PlaybackMixLoadState {
  List<String> _audioIds = const [];
  List<String> _videoIds = const [];

  List<String> get audioIds => _audioIds;
  List<String> get videoIds => _videoIds;

  bool get canMix => _audioIds.length >= 2;

  void reset() {
    _audioIds = const [];
    _videoIds = const [];
  }

  void update({
    required Iterable<String> audioIds,
    required Iterable<String> videoIds,
  }) {
    _audioIds = PlaybackMixPolicy.numericAudioIds(audioIds);
    _videoIds = PlaybackMixPolicy.numericVideoIds(videoIds);
  }
}
