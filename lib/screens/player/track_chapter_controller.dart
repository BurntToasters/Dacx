import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import '../../l10n/app_localizations.dart';
import '../../models/playable_source.dart';
import '../../playback/chapter_list_loader.dart';
import '../../playback/chapter_navigation_policy.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_mix_policy.dart';
import '../../playback/player_audio_session.dart';
import '../../playback/player_controller.dart';
import '../../playback/source_load_validation_policy.dart';
import '../../playback/track_cycle_policy.dart';
import '../../playback/track_label.dart';
import '../../services/debug_log_service.dart';
import '../../services/player_service.dart';
import '../../services/settings_service.dart';
import 'player_file_pickers.dart';

const _mixReloadDelay = Duration(milliseconds: 200);

typedef TrackChapterLog = void Function(
  String event, {
  String? message,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity severity,
});

typedef AudioTrackPickerRequest = ({
  List<AudioTrack> tracks,
  String? currentId,
});
typedef SubtitleTrackPickerRequest = ({
  List<SubtitleTrack> tracks,
  String? currentId,
});

class TrackChapterController {
  TrackChapterController({
    required this.settings,
    required this.playerService,
    required this.audioSession,
    required this.player,
    required this.playback,
    required this.pickers,
    required this.log,
    required this.isMounted,
    required this.isDisposed,
    required this.update,
    required this.l10n,
    required this.showOsd,
    required this.showMessage,
    required this.syncIdleInhibit,
    required this.captureBookmark,
    required this.reloadSourceForMixChange,
    required this.refreshMetadata,
  });

  final SettingsService settings;
  final IPlayerService playerService;
  final PlayerAudioSession audioSession;
  final PlayerController player;
  final PlaybackController playback;
  final PlayerFilePickers pickers;
  final TrackChapterLog log;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final void Function(VoidCallback fn) update;
  final AppLocalizations Function() l10n;
  final void Function(String message) showOsd;
  final void Function(String message) showMessage;
  final VoidCallback syncIdleInhibit;
  final Future<void> Function(String path) captureBookmark;
  final Future<void> Function(PlayableSource source) reloadSourceForMixChange;
  final Future<void> Function(PlayableSource source) refreshMetadata;

  final _mixLoadState = PlaybackMixLoadState();
  bool _mixReloadInFlight = false;

  void onAlbumArtTracks(Tracks tracks) {
    final artChange = player.onTracksStream(tracks);
    if (artChange.uiChanged) {
      update(() {});
      log(
        'album_art_track_changed',
        detailsBuilder: () => {
          'has_album_art_track': artChange.hasAlbumArt,
          'track_id': artChange.trackId,
        },
      );
    }

    if (!player.isAudioFile || !artChange.uiChanged) return;

    final albumArtTrack = PlayerController.firstEmbeddedAlbumArtTrack(tracks);
    if (albumArtTrack != null) {
      final gen = playback.loadGeneration;
      unawaited(
        playerService
            .setVideoTrack(albumArtTrack)
            .then((_) async {
              // Let the album-art track settle before exporting for OS chrome.
              await Future<void>.delayed(const Duration(milliseconds: 120));
              if (!isMounted() ||
                  isDisposed() ||
                  !playback.isLoadCurrent(gen)) {
                return;
              }
              final source = player.currentSource;
              if (source != null && settings.mediaSessionEnabled) {
                unawaited(refreshMetadata(source));
              }
            })
            .catchError((Object e) {
              log(
                'album_art_track_select_failed',
                message: e.toString(),
                severity: DebugSeverity.warn,
              );
            }),
      );
    }
  }

  void resetMixLoadState() => _mixLoadState.reset();

  String trackLabel(String? title, String? language, String fallbackId) =>
      formatTrackLabel(
        title: title,
        language: language,
        fallbackId: fallbackId,
        fallbackLabel: l10n().trackFallbackLabel(fallbackId),
      );

  Future<void> cycleAudioTrack() async {
    final l10n = this.l10n();
    final tracks = player.currentTracks;
    if (tracks == null || tracks.audio.length <= 1) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (!TrackCyclePolicy.canCycle(selectableCount: list.length)) return;
    final current = player.currentTrackSelection?.audio.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next =
        list[TrackCyclePolicy.nextIndex(
          currentIndex: idx,
          listLength: list.length,
        )];
    await _disableMixForManualTrackSelection();
    final ok = await playerService.setAudioTrack(next);
    if (!ok) return;
    showOsd(l10n.osdAudioTrack(trackLabel(next.title, next.language, next.id)));
  }

  Future<void> cycleSubtitleTrack() async {
    final l10n = this.l10n();
    final tracks = player.currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    if (list.length <= 1) return;
    final current = player.currentTrackSelection?.subtitle.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next =
        list[TrackCyclePolicy.nextIndex(
          currentIndex: idx,
          listLength: list.length,
        )];
    final ok = await playerService.setSubtitleTrack(next);
    if (!ok) return;
    player.subtitlesVisible = next.id != 'no';
    showOsd(
      next.id == 'no'
          ? l10n.osdSubtitlesOff
          : l10n.osdSubtitlesTrack(
              trackLabel(next.title, next.language, next.id),
            ),
    );
  }

  Future<void> toggleSubtitleVisibility() async {
    final l10n = this.l10n();
    final tracks = player.currentTracks;
    if (tracks == null) return;
    if (player.subtitlesVisible) {
      final ok = await playerService.setSubtitleTrack(SubtitleTrack.no());
      if (!ok) return;
      player.subtitlesVisible = false;
      showOsd(l10n.osdSubtitlesOff);
    } else {
      final candidate = tracks.subtitle.firstWhere(
        (t) => t.id != 'no' && t.id != 'auto',
        orElse: SubtitleTrack.auto,
      );
      final ok = await playerService.setSubtitleTrack(candidate);
      if (!ok) return;
      player.subtitlesVisible = true;
      showOsd(
        l10n.osdSubtitlesTrack(
          trackLabel(candidate.title, candidate.language, candidate.id),
        ),
      );
    }
  }

  AudioTrackPickerRequest? audioPickerRequest() {
    final tracks = player.currentTracks;
    if (tracks == null) return null;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    return (tracks: list, currentId: player.currentTrackSelection?.audio.id);
  }

  Future<void> selectAudioTrackFromPicker(AudioTrack selected) async {
    await _disableMixForManualTrackSelection();
    final ok = await playerService.setAudioTrack(selected);
    if (!ok && isMounted()) {
      showMessage(l10n().snackPlaybackOperationFailed(selected.id));
    }
  }

  SubtitleTrackPickerRequest? subtitlePickerRequest() {
    final tracks = player.currentTracks;
    if (tracks == null) return null;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    return (tracks: list, currentId: player.currentTrackSelection?.subtitle.id);
  }

  Future<void> selectSubtitleTrackFromPicker(SubtitleTrack selected) async {
    final ok = await playerService.setSubtitleTrack(selected);
    if (!ok) return;
    player.subtitlesVisible = selected.id != 'no';
  }

  Future<void> pickExternalAudio() async {
    final l10n = this.l10n();
    try {
      final path = await pickers.pickExternalAudioFile();
      if (path == null) return;
      await captureBookmark(path);
      final ok = await playerService.addExternalAudio(
        path,
        allowUnc: SourceOrigin.fileDialog.allowsUnc,
      );
      if (!isMounted()) return;
      showOsd(ok ? l10n.osdExternalAudioLoaded : l10n.osdExternalAudioFailed);
      if (ok) {
        cacheTracksForCurrentLoad(playerService.currentTracks);
        update(() {});
      } else {
        showMessage(l10n.osdExternalAudioFailed);
      }
    } catch (e) {
      log(
        'external_audio_pick_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (isMounted()) {
        showOsd(l10n.osdExternalAudioFailed);
        showMessage(l10n.osdExternalAudioFailed);
      }
    }
  }

  Future<void> pickExternalSubtitle() async {
    final l10n = this.l10n();
    try {
      final path = await pickers.pickExternalSubtitleFile();
      if (path == null) return;
      await captureBookmark(path);
      final ok = await playerService.addExternalSubtitle(
        path,
        allowUnc: SourceOrigin.fileDialog.allowsUnc,
      );
      if (!isMounted()) return;
      showOsd(
        ok ? l10n.osdExternalSubtitleLoaded : l10n.osdExternalSubtitleFailed,
      );
      if (ok) {
        cacheTracksForCurrentLoad(playerService.currentTracks);
        update(() {});
      } else {
        showMessage(l10n.osdExternalSubtitleFailed);
      }
    } catch (e) {
      log(
        'external_subtitle_pick_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (isMounted()) {
        showOsd(l10n.osdExternalSubtitleFailed);
        showMessage(l10n.osdExternalSubtitleFailed);
      }
    }
  }

  Future<void> refreshChaptersIfNeeded({int? gen}) async {
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final countRaw = await playerService.getProperty('chapter-list/count');
    final count = int.tryParse(countRaw ?? '') ?? 0;
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    if (!playback.chapterGate.shouldRefresh(
      path: player.currentFile,
      chapterCount: count,
    )) {
      return;
    }
    await refreshChapters(expectedCount: count, gen: gen);
    if (!isMounted() || isDisposed()) return;
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    playback.chapterGate.markFetched(
      path: player.currentFile,
      chapterCount: count,
    );
  }

  Future<void> refreshChapters({int? expectedCount, int? gen}) async {
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final l10n = this.l10n();
    final list = await ChapterListLoader.load(
      readProperty: playerService.getProperty,
      expectedCount: expectedCount,
      fallbackTitle: (i) => l10n.chapterFallbackLabel(i + 1),
    );
    if (!isMounted() || (gen != null && !playback.isLoadCurrent(gen))) return;
    update(() => player.chapters = list);
  }

  Future<void> stepChapter(int delta) async {
    final l10n = this.l10n();
    if (player.chapters.isEmpty) {
      await refreshChapters();
    }
    if (player.chapters.isEmpty) return;
    final current = await playerService.getProperty('chapter');
    final idx = int.tryParse(current ?? '') ?? 0;
    final next = ChapterNavigationPolicy.stepIndex(
      currentIndex: idx,
      delta: delta,
      chapterCount: player.chapters.length,
    );
    final ok = await playerService.setChapter(next);
    if (!ok) return;
    showOsd(l10n.osdChapter(player.chapters[next].title));
  }

  Future<void> jumpToChapter(int index) async {
    await playerService.setChapter(index);
  }

  void cacheTracksForCurrentLoad(
    Tracks tracks, {
    bool refreshChapters = false,
    int? gen,
  }) {
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final result = player.cacheTracksForLoad(
      tracks,
      mixLoadState: _mixLoadState,
      multiAudioMixEnabled: settings.multiAudioMix,
      refreshChapters: refreshChapters,
    );
    if (result.audioOnlyChanged) {
      update(() {});
      syncIdleInhibit();
      unawaited(applyMergedAudioFilters(gen: gen));
    }
    if (result.refreshChapters) {
      unawaited(refreshChaptersIfNeeded(gen: gen));
    }
    if (result.shouldRefreshMix) {
      unawaited(applyMultiAudioMix(gen: gen));
    }
  }

  Future<void> applyEqualizer() async {
    await applyMergedAudioFilters();
  }

  /// Builds and applies the EQ af chain.
  Future<void> applyMergedAudioFilters({int? gen}) async {
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final result = await audioSession.applyMergedAudioFilters();
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    if (result.failed) {
      log(
        'audio_filter_apply_failed',
        detailsBuilder: () => {'chain': result.appliedChain},
        severity: DebugSeverity.warn,
      );
    }
  }

  void toggleEqualizer() {
    final wantEnabled = !settings.eqEnabled;
    settings.eqEnabled = wantEnabled;
    unawaited(() async {
      final result = await audioSession.applyMergedAudioFilters();
      if (!isMounted() || isDisposed()) return;
      final l10n = this.l10n();
      if (result.failed) {
        settings.eqEnabled = !wantEnabled;
        showOsd(l10n.osdEqualizer(l10n.osdStateOff));
        showMessage(l10n.snackPlaybackOperationFailed('equalizer'));
        return;
      }
      showOsd(
        l10n.osdEqualizer(wantEnabled ? l10n.osdStateOn : l10n.osdStateOff),
      );
    }());
  }

  /// Applies or clears the multi-audio `lavfi-complex` graph.
  ///
  /// Returns `true` when the requested state was applied (including a clean
  /// disable). Returns `false` when enable was requested but failed; in that
  /// case the Experimental mix toggle is turned back off and the user gets
  /// OSD + snackbar feedback.
  Future<bool> applyMultiAudioMix({bool announce = false, int? gen}) async {
    if (gen != null && !playback.isLoadCurrent(gen)) return true;
    final l10n = this.l10n();
    final tracks = player.currentTracks;
    // No open media yet; keep the preference for the next multi-track file.
    if (tracks == null) return true;
    final ids = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .toList(growable: false);
    final shouldMix = settings.multiAudioMix && ids.length >= 2;
    if (!shouldMix) {
      // Always clear the property in case a previous file left a graph.
      await playerService.setProperty('lavfi-complex', '');
      if (gen != null && !playback.isLoadCurrent(gen)) return true;
      if (player.mixActive) {
        player.mixActive = false;
        if (announce) {
          showOsd(l10n.osdAudioMixOff);
        }
      }
      return true;
    }
    // Validate IDs are numeric; mpv's lavfi-complex labels are [aid<N>]
    // where <N> must be the integer track-id reported in track-list.
    final invalid = ids.where((id) => int.tryParse(id) == null).toList();
    if (invalid.isNotEmpty) {
      log(
        'multi_audio_mix_invalid_ids',
        message: 'non-numeric audio track ids: ${invalid.join(',')}',
        severity: DebugSeverity.warn,
      );
      await _revertMultiAudioMixFailure(l10n.osdAudioMixUnsupportedIds);
      return false;
    }
    final videoTrackId = PlaybackMixPolicy.passthroughVideoTrackId(
      videoIds: tracks.video.map((t) => t.id),
      isAlbumArtOrImage: (id) {
        for (final track in tracks.video) {
          if (track.id == id) {
            return track.albumart == true || track.image == true;
          }
        }
        return false;
      },
    );
    final chain = PlaybackMixPolicy.buildLavfiComplex(
      audioIds: ids,
      videoTrackId: videoTrackId,
    );
    log(
      'multi_audio_mix_apply',
      detailsBuilder: () => {
        'track_count': ids.length,
        'track_ids': ids.join(','),
        'chain': chain,
      },
    );
    final ok = await playerService.setProperty('lavfi-complex', chain);
    if (gen != null && !playback.isLoadCurrent(gen)) return true;
    if (ok) {
      final wasActive = player.mixActive;
      player.mixActive = true;
      if (announce || !wasActive) {
        showOsd(l10n.osdAudioMixActive(ids.length));
      }
      return true;
    }
    log('multi_audio_mix_setproperty_failed', severity: DebugSeverity.warn);
    await _revertMultiAudioMixFailure(l10n.osdAudioMixFailed);
    return false;
  }

  Future<void> _revertMultiAudioMixFailure(String message) async {
    player.mixActive = false;
    if (settings.multiAudioMix) {
      settings.multiAudioMix = false;
    }
    await playerService.setProperty('lavfi-complex', '');
    if (!isMounted() || isDisposed()) return;
    showOsd(message);
    showMessage(message);
  }

  Future<void> reloadCurrentForMixChange() async {
    final source = player.currentSource;
    if (source == null) return;
    if (_mixReloadInFlight) return;
    _mixReloadInFlight = true;
    try {
      final savedPos = player.position;
      await reloadSourceForMixChange(source);
      if (savedPos > Duration.zero) {
        await Future<void>.delayed(_mixReloadDelay);
        if (isMounted() && !isDisposed() && player.currentSource == source) {
          unawaited(playerService.seek(savedPos));
        }
      }
    } finally {
      _mixReloadInFlight = false;
    }
  }

  Future<void> _disableMixForManualTrackSelection() async {
    if (!settings.multiAudioMix && !player.mixActive) return;
    final wasActive = player.mixActive;
    if (settings.multiAudioMix) {
      settings.multiAudioMix = false;
    }
    await playerService.setProperty('lavfi-complex', '');
    player.mixActive = false;
    if (wasActive) {
      await reloadCurrentForMixChange();
    }
  }
}
