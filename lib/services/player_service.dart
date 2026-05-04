import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

class PlayerService {
  PlayerService() : player = Player();

  final Player player;
  final StreamController<PlayerErrorEvent> _errorController =
      StreamController<PlayerErrorEvent>.broadcast();

  bool _disposed = false;

  bool get isDisposed => _disposed;

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;
  Stream<bool> get playingStream => player.stream.playing;
  Stream<double> get volumeStream => player.stream.volume;
  Stream<bool> get completedStream => player.stream.completed;
  Stream<Tracks> get tracksStream => player.stream.tracks;
  Stream<Track> get trackStream => player.stream.track;
  Stream<PlayerErrorEvent> get errorStream => _errorController.stream;

  Future<void> _guard(String op, Future<void> Function() body) async {
    if (_disposed) return;
    try {
      await body();
    } catch (e, st) {
      if (!_errorController.isClosed) {
        _errorController.add(PlayerErrorEvent(op, e, st));
      }
      rethrow;
    }
  }

  Future<T?> _guardValue<T>(String op, Future<T?> Function() body) async {
    if (_disposed) return null;
    try {
      return await body();
    } catch (e, st) {
      if (!_errorController.isClosed) {
        _errorController.add(PlayerErrorEvent(op, e, st));
      }
      return null;
    }
  }

  Future<void> open(String filePath, {bool play = true}) =>
      _guard('open', () => player.open(Media(filePath), play: play));

  Future<void> playPause() => _guard('playPause', player.playOrPause);

  Future<void> stop() => _guard('stop', player.stop);

  Future<void> seek(Duration position) =>
      _guard('seek', () => player.seek(position));

  Future<void> setVolume(double volume) =>
      _guard('setVolume', () => player.setVolume(volume));

  Future<void> setRate(double rate) =>
      _guard('setRate', () => player.setRate(rate));

  Future<void> setPlaylistMode(PlaylistMode mode) =>
      _guard('setPlaylistMode', () => player.setPlaylistMode(mode));

  Future<void> setVideoTrack(VideoTrack track) =>
      _guard('setVideoTrack', () => player.setVideoTrack(track));

  Future<void> setAudioTrack(AudioTrack track) =>
      _guard('setAudioTrack', () => player.setAudioTrack(track));

  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _guard('setSubtitleTrack', () => player.setSubtitleTrack(track));

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
      _guardValue<Uint8List>(
        'screenshot',
        () => player.screenshot(format: format),
      );

  /// Sets a libmpv property by name. Returns true on success.
  Future<bool> setProperty(String name, String value) async {
    return await _guardValue<bool>('setProperty:$name', () async {
          final platform = player.platform;
          if (platform is NativePlayer) {
            await platform.setProperty(name, value);
            return true;
          }
          return false;
        }) ??
        false;
  }

  Future<String?> getProperty(String name) async {
    return _guardValue<String>('getProperty:$name', () async {
      final platform = player.platform;
      if (platform is NativePlayer) {
        return platform.getProperty(name);
      }
      return null;
    });
  }

  /// Applies an audio filter chain (mpv `--af`).
  Future<bool> setAudioFilter(String? chain) =>
      setProperty('af', chain ?? '');

  /// Jumps to absolute chapter index. (mpv `chapter` property)
  Future<bool> setChapter(int index) =>
      setProperty('chapter', index.toString());

  /// Steps relative chapters: positive forward, negative backward.
  Future<bool> stepChapter(int delta) async {
    final current = await getProperty('chapter');
    final idx = int.tryParse(current ?? '');
    if (idx == null) return false;
    return setChapter(idx + delta);
  }

  /// Adds an external audio file as a parallel audio source (mpv `audio-add`).
  /// Use `select` to make it active.
  Future<bool> addExternalAudio(String path, {bool auto = true}) =>
      setProperty('audio-files-add', path);

  /// Loads an external subtitle file (mpv `sub-add`).
  Future<bool> addExternalSubtitle(String path) =>
      setProperty('sub-files-add', path);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await player.dispose();
    } catch (_) {
    } finally {
      await _errorController.close();
    }
  }
}

class PlayerErrorEvent {
  PlayerErrorEvent(this.operation, this.error, this.stackTrace);
  final String operation;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'PlayerService($operation): $error';
}
