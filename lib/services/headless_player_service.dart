import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'player_service.dart';

/// In-memory [IPlayerService] for widget tests without libmpv.
@visibleForTesting
class HeadlessPlayerService implements IPlayerService {
  HeadlessPlayerService() {
    _tracksState = const Tracks(audio: [], video: [], subtitle: []);
  }

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<double> _volumeCtrl =
      StreamController<double>.broadcast();
  final StreamController<bool> _completedCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Tracks> _tracksCtrl =
      StreamController<Tracks>.broadcast();
  final StreamController<Track> _trackCtrl =
      StreamController<Track>.broadcast();
  final StreamController<int?> _videoWidthCtrl =
      StreamController<int?>.broadcast();
  final StreamController<PlayerErrorEvent> _errorCtrl =
      StreamController<PlayerErrorEvent>.broadcast();

  late Tracks _tracksState;
  final Map<String, String> _properties = {};
  bool _disposed = false;
  bool _isPlaying = false;
  final List<({String path, bool play})> _openCalls = [];
  int playPauseInvocations = 0;
  final List<AudioTrack> _audioTrackCalls = [];
  final List<SubtitleTrack> _subtitleTrackCalls = [];
  final List<({String name, String value})> _propertyCalls = [];
  final List<PlaylistMode> _playlistModeCalls = [];
  Object? _openError;
  Uint8List? screenshotBytes;
  Duration _openDelay = Duration.zero;

  @visibleForTesting
  set openError(Object? value) => _openError = value;

  @visibleForTesting
  set screenshotResult(Uint8List? value) => screenshotBytes = value;

  @visibleForTesting
  set openDelay(Duration value) => _openDelay = value;

  @override
  bool get isDisposed => _disposed;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<double> get volumeStream => _volumeCtrl.stream;

  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  @override
  Stream<Tracks> get tracksStream => _tracksCtrl.stream;

  @override
  Stream<Track> get trackStream => _trackCtrl.stream;

  @override
  Stream<int?> get videoWidthStream => _videoWidthCtrl.stream;

  @override
  Stream<PlayerErrorEvent> get errorStream => _errorCtrl.stream;

  @override
  Tracks get currentTracks => _tracksState;

  @override
  Future<void> open(String filePath, {bool play = true}) async {
    if (_disposed) return;
    if (_openError != null) throw _openError!;
    if (_openDelay > Duration.zero) {
      await Future<void>.delayed(_openDelay);
    }
    _openCalls.add((path: filePath, play: play));
    _properties['path'] = filePath;
    if (play) {
      _isPlaying = true;
      _playingCtrl.add(true);
    }
  }

  @visibleForTesting
  List<({String path, bool play})> get openCalls =>
      List.unmodifiable(_openCalls);

  @override
  Future<void> play() async {
    if (_disposed) return;
    _isPlaying = true;
    _playingCtrl.add(true);
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _isPlaying = false;
    _playingCtrl.add(false);
  }

  @override
  Future<void> playPause() async {
    if (_disposed) return;
    playPauseInvocations++;
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _isPlaying = false;
    _playingCtrl.add(false);
    _positionCtrl.add(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _positionCtrl.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _volumeCtrl.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPlaylistMode(PlaylistMode mode) async {
    if (_disposed) return;
    _playlistModeCalls.add(mode);
  }

  @visibleForTesting
  List<PlaylistMode> get playlistModeCalls =>
      List.unmodifiable(_playlistModeCalls);

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_disposed) return;
    _audioTrackCalls.add(track);
    _trackCtrl.add(
      Track(
        audio: track,
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      ),
    );
  }

  @visibleForTesting
  List<AudioTrack> get audioTrackCalls => List.unmodifiable(_audioTrackCalls);

  @override
  Future<void> setVideoTrack(VideoTrack track) async {}

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_disposed) return;
    _subtitleTrackCalls.add(track);
    _trackCtrl.add(
      Track(
        audio: const AudioTrack('auto', 'auto', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: track,
      ),
    );
  }

  @visibleForTesting
  List<SubtitleTrack> get subtitleTrackCalls =>
      List.unmodifiable(_subtitleTrackCalls);

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async =>
      screenshotBytes;

  @visibleForTesting
  List<({String name, String value})> get propertyCalls =>
      List.unmodifiable(_propertyCalls);

  @override
  Future<bool> setProperty(String name, String value) async {
    if (_disposed) return false;
    _properties[name] = value;
    _propertyCalls.add((name: name, value: value));
    return true;
  }

  @override
  Future<String?> getProperty(String name) async {
    if (_disposed) return null;
    return _properties[name];
  }

  @override
  Future<bool> setAudioFilter(String? chain) => setProperty('af', chain ?? '');

  @override
  Future<bool> setChapter(int index) =>
      setProperty('chapter', index.toString());

  @override
  Future<bool> stepChapter(int delta) async {
    final current = await getProperty('chapter');
    final idx = int.tryParse(current ?? '');
    if (idx == null) return false;
    return setChapter(idx + delta);
  }

  @override
  Future<bool> addExternalAudio(String path) =>
      setProperty('audio-files-add', path);

  @override
  Future<bool> addExternalSubtitle(String path) =>
      setProperty('sub-files-add', path);

  /// Test helper to push synthetic stream events into listeners.
  @visibleForTesting
  void emitDuration(Duration duration) {
    if (_disposed) return;
    _durationCtrl.add(duration);
  }

  @visibleForTesting
  void emitPlaying(bool playing) {
    if (_disposed) return;
    _isPlaying = playing;
    _playingCtrl.add(playing);
  }

  @visibleForTesting
  void emitPosition(Duration position) {
    if (_disposed) return;
    _positionCtrl.add(position);
  }

  @visibleForTesting
  void emitTracks(Tracks tracks) {
    if (_disposed) return;
    _tracksState = tracks;
    _tracksCtrl.add(tracks);
  }

  @visibleForTesting
  void emitTrack(Track track) {
    if (_disposed) return;
    _trackCtrl.add(track);
  }

  @visibleForTesting
  void emitVideoWidth(int? width) {
    if (_disposed) return;
    _videoWidthCtrl.add(width);
  }

  @visibleForTesting
  void emitCompleted(bool completed) {
    if (_disposed) return;
    _completedCtrl.add(completed);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _volumeCtrl.close();
    await _completedCtrl.close();
    await _tracksCtrl.close();
    await _trackCtrl.close();
    await _videoWidthCtrl.close();
    await _errorCtrl.close();
  }
}
