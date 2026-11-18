import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../playback/player_controller.dart';
import '../../playback/player_settings_sync.dart';
import '../../services/advanced_playback_controller.dart';
import '../../services/debug_log_service.dart';
import '../../services/player_service.dart';
import '../../services/seek_preview_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_log.dart';
import 'player_transport_controller.dart';
import 'player_window_controller.dart';
import 'track_chapter_controller.dart';

class PlayerSettingsApplier {
  PlayerSettingsApplier({
    required this.settings,
    required this.advancedPlayback,
    required this.playerService,
    required this.player,
    required this.tracks,
    required this.media,
    required this.seekPreview,
    required this.window,
    required this.transport,
    required this.log,
    required this.hasCurrentFile,
    required this.isMounted,
    required this.update,
  });

  final SettingsService settings;
  final AdvancedPlaybackController advancedPlayback;
  final IPlayerService playerService;
  final PlayerController player;
  final TrackChapterController tracks;
  final MediaSessionCoordinator media;
  final SeekPreviewService seekPreview;
  final PlayerWindowController window;
  final PlayerTransportController transport;
  final PlayerDebugLog log;
  final bool Function() hasCurrentFile;
  final bool Function() isMounted;
  final void Function(VoidCallback fn) update;

  PlayerSettingsSyncState _state = const PlayerSettingsSyncState();

  void captureInitialState() {
    _state = PlayerSettingsSyncState(
      lastSpeed: settings.speed,
      lastLoopMode: settings.loopMode,
      lastAlwaysOnTop: settings.alwaysOnTop,
      lastMediaSessionEnabled: settings.mediaSessionEnabled,
      lastPlaylistShuffle: settings.playlistShuffle,
      lastHwDec: settings.hwDec,
      lastMultiAudioMix: settings.multiAudioMix,
      lastEqEnabled: settings.eqEnabled,
      lastEqBands: List<double>.from(settings.eqBands),
    );
  }

  void onSettingsChanged() {
    unawaited(
      advancedPlayback.setEnabled(settings.advancedPlaybackToolsEnabled),
    );
    log(
      'settings_applied_to_player',
      category: DebugLogCategory.settings,
      detailsBuilder: () => {
        'speed': settings.speed.toStringAsFixed(2),
        'loop_mode': settings.loopMode.name,
        'always_on_top': settings.alwaysOnTop,
        'hwdec': settings.hwDec,
      },
    );

    final (delta, nextState) = PlayerSettingsSync.diff(
      state: _state,
      settings: settings,
    );
    _state = nextState;

    if (delta.speed != null) {
      transport.applySpeed(delta.speed!);
      media.updateRate(delta.speed!);
    }

    if (delta.loopMode != null) {
      transport.applyLoopMode(delta.loopMode!);
      media.updateLoopMode(delta.loopMode!);
    }

    final settingsVolume = settings.volume;
    if ((settingsVolume - player.volume).abs() > 0.01) {
      update(() => player.volume = settingsVolume);
      unawaited(
        playerService.setVolume(settingsVolume).catchError((Object e) {
          log(
            'settings_volume_apply_failed',
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }),
      );
    }

    if (delta.audioFilters) {
      unawaited(tracks.applyMergedAudioFilters());
    }

    if (delta.multiAudioMix) {
      unawaited(() async {
        final applied = await tracks.applyMultiAudioMix(announce: true);
        if (hasCurrentFile() && applied) {
          await tracks.reloadCurrentForMixChange();
        }
      }());
    }

    if (delta.mediaSessionEnabled != null) {
      media.setEnabled(delta.mediaSessionEnabled!);
    }

    if (delta.playlistShuffle != null) {
      transport.setShuffle(delta.playlistShuffle!);
    }

    if (delta.hwDec != null) {
      transport.applyHwDec(delta.hwDec!);
    }

    if (delta.seekPreviewEnabled != null) {
      unawaited(seekPreview.setEnabled(delta.seekPreviewEnabled!));
      final source = player.currentSource;
      if (delta.seekPreviewEnabled! &&
          source != null &&
          source.isFile &&
          !player.isAudioFile) {
        unawaited(seekPreview.setSource(source.value));
      } else if (!delta.seekPreviewEnabled!) {
        unawaited(seekPreview.setSource(null));
      }
    }

    if (delta.alwaysOnTop != null) {
      window.applyAlwaysOnTop(delta.alwaysOnTop!);
    }

    if (isMounted()) {
      update(() {});
    }
  }
}
