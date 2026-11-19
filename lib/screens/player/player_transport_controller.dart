import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../l10n/app_localizations.dart';
import '../../playback/playback_speed_policy.dart';
import '../../playback/player_controller.dart';
import '../../playback/player_path_utils.dart';
import '../../playback/volume_policy.dart';
import '../../services/debug_log_service.dart';
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_log.dart';
import 'player_window_controller.dart';

class PlayerTransportController {
  PlayerTransportController({
    required this.settings,
    required this.playerService,
    required this.player,
    required this.playlist,
    required this.media,
    required this.window,
    required this.log,
    required this.isMounted,
    required this.isDisposed,
    required this.update,
    required this.l10n,
    required this.showOsd,
  });

  final SettingsService settings;
  final IPlayerService playerService;
  final PlayerController player;
  final PlaylistService Function() playlist;
  final MediaSessionCoordinator media;
  final PlayerWindowController window;
  final PlayerDebugLog log;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final void Function(VoidCallback fn) update;
  final AppLocalizations Function() l10n;
  final void Function(String message) showOsd;

  double _volumeBeforeMute = 100.0;

  void applySpeed(double speed) {
    unawaited(
      playerService.setRate(speed).catchError((Object e) {
        log(
          'playback_rate_apply_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    log(
      'playback_rate_applied',
      detailsBuilder: () => {'rate': speed.toStringAsFixed(2)},
    );
  }

  void setPlaybackSpeed(double speed, {required String source}) {
    settings.speed = speed;
    applySpeed(speed);
    media.updateRate(speed);
    if (isMounted()) {
      showOsd(PlaybackSpeedPolicy.formatLabel(speed));
      update(() {});
    }
    log(
      'playback_speed_changed',
      category: DebugLogCategory.ui,
      detailsBuilder: () => {
        'value': speed.toStringAsFixed(2),
        'source': source,
      },
    );
  }

  void cyclePlaybackSpeed() {
    setPlaybackSpeed(
      PlaybackSpeedPolicy.cycleNext(settings.speed),
      source: 'cycle',
    );
  }

  void nudgePlaybackSpeed({required bool faster}) {
    final next = faster
        ? PlaybackSpeedPolicy.stepFaster(settings.speed)
        : PlaybackSpeedPolicy.stepSlower(settings.speed);
    if (next == settings.speed) return;
    setPlaybackSpeed(next, source: faster ? 'faster' : 'slower');
  }

  void applyHwDec(String value) {
    unawaited(
      playerService
          .setProperty('hwdec', value)
          .then((applied) {
            if (applied) {
              log(
                'hwdec_property_applied',
                category: DebugLogCategory.hwaccel,
                detailsBuilder: () => {'hwdec': value},
              );
            } else {
              log(
                'hwdec_property_unavailable',
                category: DebugLogCategory.hwaccel,
                detailsBuilder: () => {'hwdec': value},
                severity: DebugSeverity.warn,
              );
            }
          })
          .catchError((Object e) {
            log(
              'hwdec_property_failed',
              category: DebugLogCategory.hwaccel,
              message: e.toString(),
              detailsBuilder: () => {'hwdec': value},
              severity: DebugSeverity.warn,
            );
          }),
    );
    // media_kit reuses one native controller per player, so a new
    // VideoController cannot change hwdec at runtime. Only the mpv property
    // above applies; the controller from initState stays in place.
  }

  /// Keeps settings, playlist, and OS media-session shuffle in sync.
  void setShuffle(bool on) {
    if (settings.playlistShuffle != on) {
      settings.playlistShuffle = on;
    }
    playlist().setShuffle(on);
    media.updateShuffle(on);
  }

  void applyLoopMode(LoopMode mode) {
    final plMode = switch (mode) {
      LoopMode.none => PlaylistMode.none,
      LoopMode.single => PlaylistMode.single,
      // Queue looping is handled in _advancePlaylist via wrapped indexing.
      LoopMode.loop => PlaylistMode.none,
    };
    unawaited(
      playerService.setPlaylistMode(plMode).catchError((Object e) {
        log(
          'loop_mode_apply_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    log('loop_mode_applied', detailsBuilder: () => {'loop_mode': mode.name});
  }

  bool get canStepVideoFrame {
    final source = player.currentSource;
    if (source == null || player.isPlaying || player.isAudioFile) {
      return false;
    }
    final extension = source.extension?.toLowerCase();
    return player.hasVideoOutput ||
        (extension != null &&
            PlayerPathUtils.videoExtensions.contains(extension));
  }

  Future<void> stepFrame({required bool forward}) async {
    final stepped = await playerService.stepFrame(forward: forward);
    if (stepped || isDisposed()) return;
    log(
      'shortcut_frame_step_failed',
      message: forward ? 'forward' : 'backward',
      severity: DebugSeverity.warn,
    );
  }

  void seekRelative(Duration offset) {
    final target = PlayerController.clampSeekTarget(
      position: player.position,
      offset: offset,
      duration: player.duration,
    );
    if (target == null) return;
    unawaited(
      playerService.seek(target).catchError((Object e) {
        log(
          'seek_relative_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    log(
      'seek_relative',
      detailsBuilder: () => {'target_ms': target.inMilliseconds},
    );
  }

  void onSeekStart() => player.isSeeking = true;

  void onSeekChange(double value) {
    update(() {
      player.position = Duration(milliseconds: value.toInt());
    });
  }

  void onSeekEnd(double value) {
    player.isSeeking = false;
    unawaited(
      playerService.seek(Duration(milliseconds: value.toInt())).catchError((
        Object e,
      ) {
        log(
          'seek_slider_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
  }

  Future<void> onControlPlayPause() async {
    log('control_play_pause_pressed', category: DebugLogCategory.ui);
    try {
      await playerService.playPause();
    } catch (e) {
      log(
        'control_play_pause_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  void adjustVolume(double delta) {
    final newVol = VolumePolicy.adjustVolume(
      current: player.volume,
      delta: delta,
    );
    unawaited(
      playerService.setVolume(newVol).catchError((Object e) {
        log(
          'volume_adjust_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    settings.volume = newVol;
    window.revealFullscreenChrome();
    if (isMounted()) {
      showOsd(l10n().osdVolume(newVol.round()));
    }
    log(
      'volume_adjusted',
      detailsBuilder: () => {'volume': newVol.toStringAsFixed(2)},
    );
  }

  void toggleMute() {
    final wasMuted = player.volume <= 0;
    final toggle = VolumePolicy.toggleMute(
      currentVolume: player.volume,
      volumeBeforeMute: _volumeBeforeMute,
    );
    _volumeBeforeMute = toggle.volumeBeforeMute;
    unawaited(
      playerService.setVolume(toggle.newVolume).catchError((Object e) {
        log(
          'mute_toggle_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    settings.volume = toggle.newVolume;
    window.revealFullscreenChrome();
    if (isMounted()) {
      final strings = l10n();
      showOsd(
        toggle.newVolume <= 0
            ? strings.osdMuted
            : strings.osdVolume(toggle.newVolume.round()),
      );
    }
    log(
      wasMuted ? 'mute_disabled' : 'mute_enabled',
      detailsBuilder: () => wasMuted
          ? {'restored_volume': toggle.newVolume}
          : {'previous_volume': toggle.volumeBeforeMute},
    );
  }
}
