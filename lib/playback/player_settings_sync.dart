import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// Tracks last-applied settings side effects for [PlayerSettingsSync.diff].
@immutable
class PlayerSettingsSyncState {
  const PlayerSettingsSyncState({
    this.lastSpeed,
    this.lastLoopMode,
    this.lastAlwaysOnTop,
    this.lastMediaSessionEnabled,
    this.lastPlaylistShuffle,
    this.lastMultiAudioMix,
    this.lastAudioWaveformEnabled,
    this.lastEqEnabled,
    this.lastEqBands,
  });

  final double? lastSpeed;
  final LoopMode? lastLoopMode;
  final bool? lastAlwaysOnTop;
  final bool? lastMediaSessionEnabled;
  final bool? lastPlaylistShuffle;
  final bool? lastMultiAudioMix;
  final bool? lastAudioWaveformEnabled;
  final bool? lastEqEnabled;
  final List<double>? lastEqBands;

  PlayerSettingsSyncState copyWith({
    double? lastSpeed,
    LoopMode? lastLoopMode,
    bool? lastAlwaysOnTop,
    bool? lastMediaSessionEnabled,
    bool? lastPlaylistShuffle,
    bool? lastMultiAudioMix,
    bool? lastAudioWaveformEnabled,
    bool? lastEqEnabled,
    List<double>? lastEqBands,
  }) {
    return PlayerSettingsSyncState(
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastLoopMode: lastLoopMode ?? this.lastLoopMode,
      lastAlwaysOnTop: lastAlwaysOnTop ?? this.lastAlwaysOnTop,
      lastMediaSessionEnabled:
          lastMediaSessionEnabled ?? this.lastMediaSessionEnabled,
      lastPlaylistShuffle: lastPlaylistShuffle ?? this.lastPlaylistShuffle,
      lastMultiAudioMix: lastMultiAudioMix ?? this.lastMultiAudioMix,
      lastAudioWaveformEnabled:
          lastAudioWaveformEnabled ?? this.lastAudioWaveformEnabled,
      lastEqEnabled: lastEqEnabled ?? this.lastEqEnabled,
      lastEqBands: lastEqBands ?? this.lastEqBands,
    );
  }
}

/// Describes which player side effects should run after a settings change.
@immutable
class PlayerSettingsSyncDelta {
  const PlayerSettingsSyncDelta({
    this.speed,
    this.loopMode,
    this.audioFilters = false,
    this.multiAudioMix = false,
    this.mediaSessionEnabled,
    this.playlistShuffle,
    this.alwaysOnTop,
    this.rebuildUi = false,
  });

  final double? speed;
  final LoopMode? loopMode;
  final bool audioFilters;
  final bool multiAudioMix;
  final bool? mediaSessionEnabled;
  final bool? playlistShuffle;
  final bool? alwaysOnTop;
  final bool rebuildUi;

  bool get isEmpty =>
      speed == null &&
      loopMode == null &&
      !audioFilters &&
      !multiAudioMix &&
      mediaSessionEnabled == null &&
      playlistShuffle == null &&
      alwaysOnTop == null &&
      !rebuildUi;
}

abstract final class PlayerSettingsSync {
  static (PlayerSettingsSyncDelta delta, PlayerSettingsSyncState nextState)
  diff({
    required PlayerSettingsSyncState state,
    required SettingsService settings,
  }) {
    var next = state;
    double? speed;
    LoopMode? loopMode;
    var audioFilters = false;
    var multiAudioMix = false;
    bool? mediaSessionEnabled;
    bool? playlistShuffle;
    bool? alwaysOnTop;

    if (state.lastSpeed != settings.speed) {
      speed = settings.speed;
      next = next.copyWith(lastSpeed: settings.speed);
    }

    if (state.lastLoopMode != settings.loopMode) {
      loopMode = settings.loopMode;
      next = next.copyWith(lastLoopMode: settings.loopMode);
    }

    final audioChanged =
        state.lastAudioWaveformEnabled != settings.audioWaveformEnabled ||
        state.lastEqEnabled != settings.eqEnabled ||
        !listEquals(state.lastEqBands, settings.eqBands);
    if (audioChanged) {
      audioFilters = true;
      next = next.copyWith(
        lastAudioWaveformEnabled: settings.audioWaveformEnabled,
        lastEqEnabled: settings.eqEnabled,
        lastEqBands: List<double>.from(settings.eqBands),
      );
    }

    if (state.lastMultiAudioMix != settings.multiAudioMix) {
      multiAudioMix = true;
      next = next.copyWith(lastMultiAudioMix: settings.multiAudioMix);
    }

    if (state.lastMediaSessionEnabled != settings.mediaSessionEnabled) {
      mediaSessionEnabled = settings.mediaSessionEnabled;
      next = next.copyWith(
        lastMediaSessionEnabled: settings.mediaSessionEnabled,
      );
    }

    if (state.lastPlaylistShuffle != settings.playlistShuffle) {
      playlistShuffle = settings.playlistShuffle;
      next = next.copyWith(lastPlaylistShuffle: settings.playlistShuffle);
    }

    if (state.lastAlwaysOnTop != settings.alwaysOnTop) {
      alwaysOnTop = settings.alwaysOnTop;
      next = next.copyWith(lastAlwaysOnTop: settings.alwaysOnTop);
    }

    final delta = PlayerSettingsSyncDelta(
      speed: speed,
      loopMode: loopMode,
      audioFilters: audioFilters,
      multiAudioMix: multiAudioMix,
      mediaSessionEnabled: mediaSessionEnabled,
      playlistShuffle: playlistShuffle,
      alwaysOnTop: alwaysOnTop,
      rebuildUi:
          speed != null ||
          loopMode != null ||
          audioFilters ||
          multiAudioMix ||
          mediaSessionEnabled != null ||
          playlistShuffle != null ||
          alwaysOnTop != null,
    );

    return (delta, next);
  }
}
