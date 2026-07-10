import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// Playback API surface used by [PlayerScreen] and related services.
abstract class IPlayerService {
  bool get isDisposed;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<double> get volumeStream;
  Stream<bool> get completedStream;
  Stream<Tracks> get tracksStream;
  Stream<Track> get trackStream;
  Stream<int?> get videoWidthStream;
  Stream<PlayerErrorEvent> get errorStream;

  Tracks get currentTracks;

  Future<void> open(String filePath, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playPause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setPlaylistMode(PlaylistMode mode);
  Future<void> setVideoTrack(VideoTrack track);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<Uint8List?> screenshot({String format = 'image/jpeg'});
  Future<bool> setProperty(String name, String value);
  Future<String?> getProperty(String name);
  Future<bool> setAudioFilter(String? chain);
  Future<bool> setChapter(int index);
  Future<bool> stepChapter(int delta);
  Future<bool> addExternalAudio(String path);
  Future<bool> addExternalSubtitle(String path);
  Future<void> dispose();
}

class PlayerService implements IPlayerService {
  PlayerService({Player? player}) : player = player ?? Player();

  final Player player;
  final StreamController<PlayerErrorEvent> _errorController =
      StreamController<PlayerErrorEvent>.broadcast();

  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<double> get volumeStream => player.stream.volume;
  @override
  Stream<bool> get completedStream => player.stream.completed;
  @override
  Stream<Tracks> get tracksStream => player.stream.tracks;
  @override
  Stream<Track> get trackStream => player.stream.track;
  @override
  Stream<int?> get videoWidthStream => player.stream.width;
  @override
  Stream<PlayerErrorEvent> get errorStream => _errorController.stream;

  @override
  Tracks get currentTracks => player.state.tracks;

  Future<void> _guard(String op, Future<void> Function() body) async {
    if (_disposed) return;
    try {
      await body();
    } catch (e, st) {
      if (!_errorController.isClosed) {
        _errorController.add(PlayerErrorEvent(op, e, st));
      }
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

  @override
  Future<void> open(String filePath, {bool play = true}) async {
    if (_disposed) return;
    await player.open(Media(filePath), play: play);
  }

  @override
  Future<void> play() => _guard('play', player.play);

  @override
  Future<void> pause() => _guard('pause', player.pause);

  @override
  Future<void> playPause() => _guard('playPause', player.playOrPause);

  @override
  Future<void> stop() => _guard('stop', player.stop);

  @override
  Future<void> seek(Duration position) =>
      _guard('seek', () => player.seek(position));

  @override
  Future<void> setVolume(double volume) =>
      _guard('setVolume', () => player.setVolume(volume));

  @override
  Future<void> setRate(double rate) =>
      _guard('setRate', () => player.setRate(rate));

  @override
  Future<void> setPlaylistMode(PlaylistMode mode) =>
      _guard('setPlaylistMode', () => player.setPlaylistMode(mode));

  @override
  Future<void> setVideoTrack(VideoTrack track) =>
      _guard('setVideoTrack', () => player.setVideoTrack(track));

  @override
  Future<void> setAudioTrack(AudioTrack track) =>
      _guard('setAudioTrack', () => player.setAudioTrack(track));

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _guard('setSubtitleTrack', () => player.setSubtitleTrack(track));

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
      _guardValue<Uint8List>(
        'screenshot',
        () => player.screenshot(format: format),
      );

  /// Sets a libmpv property by name. Returns true on success.
  @override
  Future<bool> setProperty(String name, String value) async {
    return await _guardValue<bool>('setProperty:$name', () async {
          final platform = player.platform;
          if (platform is NativePlayer) {
            await platform.setProperty(name, value);
            if (_shouldVerifySetProperty(name)) {
              final actual = (await platform.getProperty(name)).trim();
              return actual == value.trim();
            }
            return true;
          }
          return false;
        }) ??
        false;
  }

  bool _shouldVerifySetProperty(String name) {
    switch (name) {
      case 'chapter':
      case 'hwdec':
      case 'af':
        return true;
      default:
        return false;
    }
  }

  @override
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

  @override
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
