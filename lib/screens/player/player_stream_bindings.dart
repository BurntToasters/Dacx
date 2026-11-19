import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../playback/playback_controller.dart';
import '../../playback/player_controller.dart';
import '../../playback/playlist_advance_policy.dart';
import '../../playback/subscription_bag.dart';
import '../../services/advanced_playback_controller.dart';
import '../../services/debug_log_service.dart';
import '../../services/packaged_e2e_probe.dart';
import '../../services/player_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_log.dart';
import 'player_window_controller.dart';
import 'source_load_coordinator.dart';
import 'track_chapter_controller.dart';

class PlayerStreamBindings {
  PlayerStreamBindings({
    required this.playerService,
    required this.isActive,
    required this.debugLogEnabled,
    required this.log,
    required this.update,
    required this.settings,
    required this.player,
    required this.advancedPlayback,
    required this.media,
    required this.window,
    required this.sourceLoad,
    required this.playback,
    required this.trackController,
    required this.packagedE2eProbe,
    required this.showPlaybackError,
  });

  final IPlayerService playerService;
  final bool Function() isActive;
  final bool Function() debugLogEnabled;
  final PlayerDebugLog log;
  final void Function(VoidCallback fn) update;
  final SettingsService settings;
  final PlayerController player;
  final AdvancedPlaybackController advancedPlayback;
  final MediaSessionCoordinator media;
  final PlayerWindowController window;
  final SourceLoadCoordinator sourceLoad;
  final PlaybackController playback;
  final TrackChapterController trackController;
  final PackagedE2eProbe? Function() packagedE2eProbe;
  final void Function(PlayerErrorEvent event) showPlaybackError;

  final _subscriptions = SubscriptionBag();

  void attach() {
    _subscriptions.add(
      playerService.positionStream.listen((pos) {
        if (!isActive()) return;
        advancedPlayback.setPosition(pos);
        final uiUpdate = player.onPosition(pos);
        if (uiUpdate == PositionUiUpdate.skip) return;
        if (uiUpdate == PositionUiUpdate.notify) {
          update(() {});
        }
        media.onPosition(pos);
      }),
    );
    _subscriptions.add(
      playerService.durationStream.listen((dur) {
        if (!isActive()) return;
        unawaited(window.syncCompactAspectRatio());
        final packagedProbe = packagedE2eProbe();
        if (packagedProbe != null) {
          unawaited(packagedProbe.recordDuration(dur));
        }
        advancedPlayback.setDuration(dur);
        update(() => player.duration = dur);
        media.onDuration(dur);
        if (dur.inMilliseconds > 0 && debugLogEnabled()) {
          log(
            'duration_updated',
            detailsBuilder: () => {'duration_ms': dur.inMilliseconds},
          );
        }
      }),
    );
    _subscriptions.add(
      playerService.playingStream.listen((playing) {
        if (!isActive()) return;
        final packagedProbe = packagedE2eProbe();
        if (packagedProbe != null) {
          unawaited(packagedProbe.recordPlaying(playing));
        }
        update(() => player.isPlaying = playing);
        if (playing) {
          window.onChromeHoldsChanged();
        } else {
          window.revealFullscreenChrome();
        }
        // Save on pause: the periodic saver only runs while playing, so a
        // pause (and any seek after it) would otherwise not be stored.
        if (!playing && !player.fileOpenInProgress) {
          sourceLoad.persistResumePosition();
        }
        media.onPlayingChanged(playing);
        if (debugLogEnabled()) {
          log(
            'playing_state_changed',
            detailsBuilder: () => {'playing': playing},
          );
        }
      }),
    );
    _subscriptions.add(
      playerService.volumeStream.listen((vol) {
        if (!isActive()) return;
        update(() => player.volume = vol);
        media.updateVolume(vol);
        if (debugLogEnabled()) {
          log(
            'volume_stream_updated',
            detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
          );
        }
      }),
    );
    _subscriptions.add(
      playerService.videoWidthStream.listen((w) {
        if (!isActive()) return;
        final videoOutputChanged = player.onVideoWidth(w);
        unawaited(window.syncCompactAspectRatio());
        if (videoOutputChanged) {
          update(() {});
          media.syncIdleInhibit();
          if (debugLogEnabled()) {
            log(
              'video_output_changed',
              detailsBuilder: () => {
                'has_video_output': player.hasVideoOutput,
                'width': w,
              },
            );
          }
        }
      }),
    );
    _subscriptions.add(
      playerService.tracksStream.listen((tracks) {
        if (!isActive()) return;
        trackController.onAlbumArtTracks(tracks);
        unawaited(window.syncCompactAspectRatio());
        if (sourceLoad.stopInProgress || player.fileOpenInProgress) return;
        trackController.cacheTracksForCurrentLoad(
          tracks,
          refreshChapters: true,
          gen: playback.loadGeneration,
        );
      }),
    );
    _subscriptions.add(
      playerService.errorStream.listen((event) {
        if (!isActive()) return;
        packagedE2eProbe()?.recordError(event);
        log(
          'player_operation_failed',
          message: event.toString(),
          severity: DebugSeverity.warn,
        );
        showPlaybackError(event);
      }),
    );
    _subscriptions.add(
      playerService.completedStream.listen((completed) {
        if (!isActive() || !completed) return;
        if (sourceLoad.stopInProgress || playback.loadQueue.isBusy) return;
        if (player.currentSource == null) return;
        media.onPlaybackCompleted();
        update(() => player.position = Duration.zero);
        if (debugLogEnabled()) {
          log('playback_completed');
        }
        // File ran to end → drop saved resume position.
        final source = player.currentSource;
        if (source != null && source.isFile) {
          settings.saveResumePosition(source.value, null);
        }
        // Try to advance the playlist for queue-driven loop modes.
        if (PlaylistAdvancePolicy.shouldAdvanceOnCompleted(settings.loopMode)) {
          unawaited(sourceLoad.advancePlaylist(1));
        }
      }),
    );
    _subscriptions.add(
      playerService.trackStream.listen((track) {
        if (!isActive()) return;
        player.currentTrackSelection = track;
      }),
    );
  }

  void dispose() => _subscriptions.cancelAll();
}
