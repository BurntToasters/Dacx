import 'dart:async';

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
