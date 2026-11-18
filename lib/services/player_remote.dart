import 'package:flutter/foundation.dart';

@immutable
class NowPlayingState {
  const NowPlayingState({
    this.title,
    this.artist,
    this.isPlaying = false,
    this.hasMedia = false,
    this.canGoNext = false,
    this.canGoPrevious = false,
  });

  static const NowPlayingState idle = NowPlayingState();

  final String? title;
  final String? artist;
  final bool isPlaying;
  final bool hasMedia;
  final bool canGoNext;
  final bool canGoPrevious;

  @override
  bool operator ==(Object other) =>
      other is NowPlayingState &&
      other.title == title &&
      other.artist == artist &&
      other.isPlaying == isPlaying &&
      other.hasMedia == hasMedia &&
      other.canGoNext == canGoNext &&
      other.canGoPrevious == canGoPrevious;

  @override
  int get hashCode =>
      Object.hash(title, artist, isPlaying, hasMedia, canGoNext, canGoPrevious);
}

class PlayerRemoteCommands {
  const PlayerRemoteCommands({
    required this.playPause,
    required this.next,
    required this.previous,
  });

  final Future<void> Function() playPause;
  final Future<void> Function() next;
  final Future<void> Function() previous;
}

class PlayerRemote extends ChangeNotifier
    implements ValueListenable<NowPlayingState> {
  NowPlayingState _value = NowPlayingState.idle;
  PlayerRemoteCommands? _commands;
  bool _disposed = false;

  @override
  NowPlayingState get value => _value;

  bool get isAttached => _commands != null;

  void attach(PlayerRemoteCommands commands) {
    if (_disposed) return;
    _commands = commands;
  }

  void detach(PlayerRemoteCommands commands) {
    if (_disposed) return;
    if (!identical(_commands, commands)) return;
    _commands = null;
    update(NowPlayingState.idle);
  }

  void update(NowPlayingState state) {
    if (_disposed || state == _value) return;
    _value = state;
    notifyListeners();
  }

  Future<void> playPause() async => _commands?.playPause();

  Future<void> next() async => _commands?.next();

  Future<void> previous() async => _commands?.previous();

  @override
  void dispose() {
    _disposed = true;
    _commands = null;
    super.dispose();
  }
}
