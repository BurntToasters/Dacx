import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/chapter_info.dart';
import '../../models/playable_source.dart';
import '../../playback/player_controller.dart';
import '../../playback/source_load_validation_policy.dart';
import '../../services/advanced_playback_controller.dart';
import '../../services/playlist_service.dart';
import 'source_load_coordinator.dart';

class PlayerSeeding {
  PlayerSeeding({
    required this.isActive,
    required this.update,
    required this.player,
    required this.playlist,
    required this.sourceLoad,
    required this.advancedPlayback,
  });

  final bool Function() isActive;
  final void Function(VoidCallback fn) update;
  final PlayerController player;
  final PlaylistService playlist;
  final SourceLoadCoordinator sourceLoad;
  final AdvancedPlaybackController advancedPlayback;

  void schedule({
    PlayableSource? loadedSource,
    List<PlayableSource>? playlistSources,
    List<ChapterInfo>? chapters,
    List<String>? dropPaths,
    PlayableSource? pendingLoad,
  }) {
    if (loadedSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive()) return;
        update(
          () => player.beginSourceLoad(
            loadedSource,
            loadedSource.extension ?? '',
          ),
        );
        unawaited(advancedPlayback.setSource(loadedSource));
      });
    }

    if (playlistSources != null && playlistSources.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive()) return;
        playlist.replaceSources(playlistSources);
      });
    }

    if (chapters != null && chapters.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive()) return;
        update(() => player.chapters = chapters);
      });
    }

    if (dropPaths != null && dropPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive()) return;
        sourceLoad.applyDroppedPaths(dropPaths, origin: SourceOrigin.dragDrop);
      });
    }

    if (pendingLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive()) return;
        unawaited(sourceLoad.loadSource(pendingLoad));
      });
    }
  }
}
