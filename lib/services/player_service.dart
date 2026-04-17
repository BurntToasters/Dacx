import 'package:media_kit/media_kit.dart';

class PlayerService {
  final Player player = Player();
  bool _disposed = false;

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;
  Stream<bool> get playingStream => player.stream.playing;
  Stream<double> get volumeStream => player.stream.volume;
  Stream<bool> get completedStream => player.stream.completed;

  Future<void> open(String filePath, {bool play = true}) async {
    if (_disposed) return;
    await player.open(Media(filePath), play: play);
  }

  Future<void> playPause() async {
    if (_disposed) return;
    await player.playOrPause();
  }

  Future<void> stop() async {
    if (_disposed) return;
    await player.stop();
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    await player.setVolume(volume);
  }

  Future<void> setRate(double rate) async {
    if (_disposed) return;
    await player.setRate(rate);
  }

  Future<void> setPlaylistMode(PlaylistMode mode) async {
    if (_disposed) return;
    await player.setPlaylistMode(mode);
  }

  void dispose() {
    _disposed = true;
    player.dispose();
  }
}
