import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../models/playable_source.dart';
import '../models/chapter_info.dart';
import 'playback_mix_policy.dart';
import 'player_path_utils.dart';

/// Whether a position stream tick should trigger widget rebuild.
enum PositionUiUpdate { skip, silent, notify }

/// Album-art track metadata change from a [Tracks] update.
class AlbumArtTrackChange {
  const AlbumArtTrackChange({
    required this.hasAlbumArt,
    required this.trackId,
    required this.uiChanged,
  });

  final bool hasAlbumArt;
  final String? trackId;
  final bool uiChanged;
}

/// Snapshot produced when a new source load begins.
class SourceLoadBeginState {
  const SourceLoadBeginState({
    required this.source,
    required this.isAudioByExtension,
  });

  final PlayableSource source;
  final bool isAudioByExtension;
}

/// Result of caching tracks after a successful open.
class TracksCacheResult {
  const TracksCacheResult({
    required this.tracks,
    this.inferredAudioOnly,
    this.audioOnlyChanged = false,
    this.shouldRefreshMix = false,
    this.refreshChapters = false,
  });

  final Tracks tracks;
  final bool? inferredAudioOnly;
  final bool audioOnlyChanged;
  final bool shouldRefreshMix;
  final bool refreshChapters;
}

/// Observable playback/UI state extracted from [PlayerScreen] for testability.
///
/// Concurrency (load queue, throttles) stays in [PlaybackController].
class PlayerController {
  static const int positionNotifyThresholdMs = 200;

  PlayableSource? currentSource;
  String? get currentFile => currentSource?.value;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  double volume = 100.0;
  bool isSeeking = false;

  bool isAudioFile = false;
  bool hasVideoOutput = false;
  bool hasAlbumArtTrack = false;
  String? albumArtTrackId;

  bool mixActive = false;
  String? lastAppliedAfChain;
  bool fileOpenInProgress = false;

  Tracks? currentTracks;
  Track? currentTrackSelection;
  List<ChapterInfo> chapters = const [];
  bool subtitlesVisible = true;

  bool osdVisible = false;
  String? osdTransientMessage;

  String? resumePathInProgress;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Coalesces high-frequency position ticks before UI rebuild.
  PositionUiUpdate onPosition(Duration pos) {
    if (isSeeking) return PositionUiUpdate.skip;
    final dMs = (pos.inMilliseconds - position.inMilliseconds).abs();
    final shouldRender =
        dMs >= positionNotifyThresholdMs ||
        (pos.inSeconds != position.inSeconds);
    position = pos;
    return shouldRender ? PositionUiUpdate.notify : PositionUiUpdate.silent;
  }

  void onDuration(Duration dur) {
    duration = dur;
  }

  void onPlaying(bool playing) {
    isPlaying = playing;
  }

  void onVolume(double vol) {
    volume = vol;
  }

  /// Returns true when [hasVideoOutput] changed.
  bool onVideoWidth(int? w) {
    final has = w != null && w > 0;
    if (has == hasVideoOutput) return false;
    hasVideoOutput = has;
    return true;
  }

  AlbumArtTrackChange onTracksStream(Tracks tracks) {
    currentTracks = tracks;
    final albumArtTrack = firstEmbeddedAlbumArtTrack(tracks);
    final hasAlbumArt = albumArtTrack != null;
    final nextTrackId = albumArtTrack?.id;
    final trackChanged = nextTrackId != albumArtTrackId;
    final hasArtChanged = hasAlbumArt != hasAlbumArtTrack;
    if (hasArtChanged || trackChanged) {
      hasAlbumArtTrack = hasAlbumArt;
      albumArtTrackId = nextTrackId;
    }
    return AlbumArtTrackChange(
      hasAlbumArt: hasAlbumArt,
      trackId: nextTrackId,
      uiChanged: hasArtChanged || trackChanged,
    );
  }

  SourceLoadBeginState beginSourceLoad(PlayableSource source, String ext) {
    lastAppliedAfChain = null;
    resumePathInProgress = null;
    currentSource = source;
    currentTracks = null;
    currentTrackSelection = null;
    chapters = const [];
    isAudioFile = PlayerPathUtils.isAudioExtension(ext);
    hasVideoOutput = false;
    hasAlbumArtTrack = false;
    albumArtTrackId = null;
    position = Duration.zero;
    duration = Duration.zero;
    return SourceLoadBeginState(
      source: source,
      isAudioByExtension: isAudioFile,
    );
  }

  void clearSourceOnLoadFailure() {
    currentSource = null;
    isAudioFile = false;
    albumArtTrackId = null;
    resumePathInProgress = null;
  }

  void resetTransport() {
    position = Duration.zero;
    duration = Duration.zero;
    isPlaying = false;
  }

  /// Clears loaded media surface state after user presses Stop.
  void clearMediaSurface() {
    currentSource = null;
    isAudioFile = false;
    hasVideoOutput = false;
    hasAlbumArtTrack = false;
    albumArtTrackId = null;
    position = Duration.zero;
    duration = Duration.zero;
  }

  /// Clamps a relative seek. Returns null when [duration] is unknown.
  static Duration? clampSeekTarget({
    required Duration position,
    required Duration offset,
    required Duration duration,
  }) {
    if (duration.inMilliseconds == 0) return null;
    var target = position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    return target;
  }

  TracksCacheResult cacheTracksForLoad(
    Tracks tracks, {
    required PlaybackMixLoadState mixLoadState,
    required bool multiAudioMixEnabled,
    bool refreshChapters = false,
  }) {
    currentTracks = tracks;
    final inferred = inferAudioOnlyFromTracks(tracks);
    var audioOnlyChanged = false;
    if (inferred != null && inferred != isAudioFile) {
      isAudioFile = inferred;
      audioOnlyChanged = true;
    }
    mixLoadState.update(
      audioIds: tracks.audio.map((track) => track.id),
      videoIds: tracks.video.map((track) => track.id),
    );
    final shouldRefreshMix =
        multiAudioMixEnabled &&
        mixLoadState.canMix &&
        !mixActive &&
        !fileOpenInProgress;
    return TracksCacheResult(
      tracks: tracks,
      inferredAudioOnly: inferred,
      audioOnlyChanged: audioOnlyChanged,
      shouldRefreshMix: shouldRefreshMix,
      refreshChapters: refreshChapters,
    );
  }

  static bool? inferAudioOnlyFromTracks(Tracks tracks) {
    final audioTrackCount = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .length;
    if (audioTrackCount == 0) return null;
    final videoTracks = tracks.video.where(
      (track) => track.id != 'auto' && track.id != 'no',
    );
    final hasNonArtVideo = videoTracks.any(
      (track) => track.albumart != true && track.image != true,
    );
    return !hasNonArtVideo;
  }

  static VideoTrack? firstEmbeddedAlbumArtTrack(Tracks tracks) {
    for (final track in tracks.video) {
      final id = track.id.toLowerCase();
      if (id == 'auto' || id == 'no') continue;
      if (track.albumart == true || track.image == true) {
        return track;
      }
    }
    return null;
  }

  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  String osdTitle() {
    final source = currentSource;
    if (source == null) return '';
    if (source.isFile) return p.basenameWithoutExtension(source.value);
    return source.displayName;
  }

  static String stripOsdTimestamp(String? raw) {
    if (raw == null) return '';
    final i = raw.indexOf('\u2009·\u2009');
    return i == -1 ? raw : raw.substring(0, i);
  }

  void dispose() {
    _disposed = true;
  }
}
