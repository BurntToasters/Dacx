import 'package:flutter/widgets.dart';

import '../../playback/playlist_advance_policy.dart';
import '../../playback/player_controller.dart';
import '../../services/player_remote.dart';
import '../../services/playlist_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_transport_controller.dart';
import 'source_load_coordinator.dart';

class PlayerRemoteBinding {
  PlayerRemoteBinding({
    required this.remote,
    required this.playlist,
    required this.settings,
    required this.player,
    required this.media,
    required this.sourceLoad,
    required this.transport,
    required this.isDisposed,
    required this.miniPlayerTitle,
  });

  final PlayerRemote? Function() remote;
  final PlaylistService playlist;
  final SettingsService settings;
  final PlayerController player;
  final MediaSessionCoordinator media;
  final SourceLoadCoordinator sourceLoad;
  final PlayerTransportController transport;
  final bool Function() isDisposed;
  final String Function() miniPlayerTitle;

  PlayerRemoteCommands? _commands;

  void attach() {
    final current = remote();
    if (current == null) return;
    final commands = PlayerRemoteCommands(
      playPause: transport.onControlPlayPause,
      next: () => sourceLoad.advancePlaylist(1),
      previous: () => sourceLoad.advancePlaylist(-1),
    );
    _commands = commands;
    current.attach(commands);
    playlist.addListener(sync);
    settings.addListener(sync);
  }

  void detach() {
    final commands = _commands;
    if (commands == null) return;
    _commands = null;
    playlist.removeListener(sync);
    settings.removeListener(sync);
    remote()?.detach(commands);
  }

  NowPlayingState _snapshot() {
    if (player.currentFile == null) return NowPlayingState.idle;
    final title = miniPlayerTitle();
    final artist = player.isAudioFile ? media.displayArtist : null;
    return NowPlayingState(
      title: title.isEmpty ? null : title,
      artist: artist,
      isPlaying: player.isPlaying,
      hasMedia: true,
      canGoNext: PlaylistAdvancePolicy.canGoNext(
        queueLength: playlist.length,
        loopMode: settings.loopMode,
        hasNextInOrder: playlist.hasNext,
      ),
      canGoPrevious: PlaylistAdvancePolicy.canGoPrevious(
        queueLength: playlist.length,
        loopMode: settings.loopMode,
        hasPreviousInOrder: playlist.hasPrevious,
      ),
    );
  }

  void sync() {
    if (isDisposed()) return;
    remote()?.update(_snapshot());
  }

  void syncAfterBuild() {
    final current = remote();
    if (current == null || _commands == null) return;
    if (_snapshot() == current.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => sync());
  }
}
