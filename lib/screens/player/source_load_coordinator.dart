import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/playable_source.dart';
import '../../playback/drop_path_batch_policy.dart';
import '../../playback/enqueue_policy.dart';
import '../../playback/m3u_playlist.dart';
import '../../playback/media_folder_scanner.dart';
import '../../playback/playback_controller.dart';
import '../../playback/player_controller.dart';
import '../../playback/player_path_utils.dart';
import '../../playback/playlist_advance_policy.dart';
import '../../playback/resume_playback_policy.dart';
import '../../playback/source_load_open_policy.dart';
import '../../playback/source_load_post_open_policy.dart';
import '../../playback/source_load_pre_open_policy.dart';
import '../../playback/source_load_validation_policy.dart';
import '../../playback/source_open_policy.dart';
import '../../services/advanced_playback_controller.dart';
import '../../services/bookmark_service.dart';
import '../../services/debug_log_service.dart';
import '../../services/path_probe.dart';
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/seek_preview_service.dart';
import '../../services/settings_service.dart';
import 'media_session_coordinator.dart';
import 'player_file_pickers.dart';
import 'player_messenger.dart';
import 'track_chapter_controller.dart';

const _durationPollInterval = Duration(milliseconds: 50);

typedef SourceLoadLog = void Function(
  String event, {
  DebugLogCategory category,
  String? message,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity severity,
});

class SourceLoadCoordinator {
  SourceLoadCoordinator({
    required this.settings,
    required this.playerService,
    required this.playback,
    required this.player,
    required this.playlist,
    required this.media,
    required this.tracks,
    required this.pickers,
    required this.advancedPlayback,
    required this.seekPreview,
    required this.log,
    required this.isMounted,
    required this.isDisposed,
    required this.isHeadlessMedia,
    required this.update,
    required this.l10n,
    required this.showOsd,
    required this.showMessage,
  });

  final SettingsService settings;
  final IPlayerService playerService;
  final PlaybackController playback;
  final PlayerController player;
  final PlaylistService playlist;
  final MediaSessionCoordinator media;
  final TrackChapterController tracks;
  final PlayerFilePickers pickers;
  final AdvancedPlaybackController advancedPlayback;
  final SeekPreviewService seekPreview;
  final SourceLoadLog log;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final bool Function() isHeadlessMedia;
  final void Function(VoidCallback fn) update;
  final AppLocalizations Function() l10n;
  final void Function(String message) showOsd;
  final void Function(String message) showMessage;

  bool _stopInProgress = false;
  String? _activeBookmarkToken;

  bool get stopInProgress => _stopInProgress;

  void releaseActiveBookmark() {
    final token = _activeBookmarkToken;
    if (token == null || token.isEmpty) return;
    _activeBookmarkToken = null;
    unawaited(BookmarkService.stop(token));
  }

  Future<String> _resolveSandboxedPath(String requestedPath) async {
    final scoped = await resolveBookmarkScope(requestedPath);
    if (scoped.token != null) {
      releaseActiveBookmark();
      _activeBookmarkToken = scoped.token!.isNotEmpty ? scoped.token : null;
    }
    return scoped.path;
  }

  Future<({String path, String? token})> resolveBookmarkScope(
    String requestedPath,
  ) async {
    if (!BookmarkService.isSupported) return (path: requestedPath, token: null);
    final coveringKey = settings.coveringBookmarkKey(requestedPath);
    final bookmarkKey = coveringKey ?? requestedPath;
    final bookmark = settings.fileBookmark(bookmarkKey);
    if (bookmark == null || bookmark.isEmpty) {
      return (path: requestedPath, token: null);
    }
    final resolved = await BookmarkService.resolveAndStart(bookmark);
    if (resolved == null) {
      // A covering folder bookmark may still be valid for siblings.
      if (coveringKey == null || coveringKey == requestedPath) {
        settings.removeFileBookmark(requestedPath);
      }
      return (path: requestedPath, token: null);
    }
    final bookmarkToPersist = resolved.refreshed ?? bookmark;
    if (resolved.path != bookmarkKey) {
      settings.setFileBookmark(resolved.path, bookmarkToPersist);
    } else if (resolved.stale && resolved.refreshed != null) {
      settings.setFileBookmark(bookmarkKey, resolved.refreshed!);
    }
    if (coveringKey != null && coveringKey != requestedPath) {
      return (path: requestedPath, token: resolved.token);
    }
    return (path: resolved.path, token: resolved.token);
  }

  Future<void> captureBookmarkFor(String path) async {
    if (!BookmarkService.isSupported) return;
    final bookmark = await BookmarkService.createBookmark(path);
    if (bookmark != null && bookmark.isNotEmpty) {
      settings.setFileBookmark(path, bookmark);
    }
  }

  void _handleLoadValidationFailure({
    required SourceLoadValidationFailure failure,
    required Map<String, Object?> Function() detailsBuilder,
    _LoadFailureBatch? batch,
  }) {
    final reaction = SourceLoadValidationPolicy.reactionFor(failure);
    if (reaction.logEvent.isNotEmpty) {
      log(
        reaction.logEvent,
        detailsBuilder: detailsBuilder,
        severity: DebugSeverity.warn,
      );
    }
    if (reaction.shouldPruneRecentFiles) {
      if (batch != null) {
        batch.pruneRecents = true;
      } else {
        unawaited(settings.pruneRecentFiles());
      }
    }
    if (!isMounted() || reaction.userMessage == null) return;
    final message = PlayerMessenger.loadUserMessageText(
      l10n(),
      reaction.userMessage!,
    );
    if (batch != null) {
      batch.add(message);
      return;
    }
    showMessage(message);
  }

  void _flushLoadFailureBatch(_LoadFailureBatch batch) {
    if (batch.pruneRecents) {
      unawaited(settings.pruneRecentFiles());
    }
    if (!isMounted() || batch.count == 0) return;
    final message = batch.count == 1
        ? batch.firstMessage!
        : l10n().snackLoadFailuresSummary(batch.count);
    showMessage(message);
  }

  Future<void> openRequestedFile(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.forwarded,
  }) async {
    await openRequestedFileRequest(
      OpenFileRequest(path: filePath),
      forcePlay: forcePlay,
      origin: origin,
    );
  }

  Future<void> openRequestedFileRequest(
    OpenFileRequest request, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.forwarded,
  }) async {
    final bookmark = request.bookmark;
    if (bookmark != null && BookmarkService.isSupported) {
      settings.setFileBookmark(request.path, bookmark);
    }
    final filePath = request.path;
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return;
    if (player.currentFile == trimmed) {
      log(
        'open_requested_same_file',
        detailsBuilder: () => {
          'path': trimmed,
          'force_play': forcePlay,
          'is_playing': player.isPlaying,
        },
      );
      if (SourceOpenPolicy.shouldResumeSameFile(
        forcePlay: forcePlay,
        isPlaying: player.isPlaying,
      )) {
        unawaited(playerService.playPause().catchError((_) {}));
        return;
      }
      if (SourceOpenPolicy.shouldRestartSameFile(
        forcePlay: forcePlay,
        isPlaying: player.isPlaying,
      )) {
        await _loadFile(trimmed, forcePlay: true, origin: origin);
        return;
      }
      return;
    }
    log(
      'open_requested',
      detailsBuilder: () => {'path': trimmed, 'force_play': forcePlay},
    );
    await _loadFile(trimmed, forcePlay: forcePlay, origin: origin);
  }

  Future<void> openRequestedFileBatch(List<OpenFileRequest> requests) async {
    if (BookmarkService.isSupported) {
      for (final request in requests) {
        final bookmark = request.bookmark;
        if (bookmark != null) settings.setFileBookmark(request.path, bookmark);
      }
    }
    applyDroppedPaths(
      requests.map((request) => request.path),
      origin: SourceOrigin.forwarded,
    );
  }

  Future<void> _loadFile(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    return openPathOrPlaylist(filePath, forcePlay: forcePlay, origin: origin);
  }

  Future<void> openPathOrPlaylist(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.other,
  }) async {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return;
    if (PlayableSource.isSupportedUrl(trimmed)) {
      await loadSource(PlayableSource.url(trimmed), forcePlay: forcePlay);
      return;
    }
    if (PlayerPathUtils.isUnsafeOpenPath(trimmed, allowUnc: origin.allowsUnc)) {
      _handleLoadValidationFailure(
        failure: SourceLoadValidationFailure.unsafePath,
        detailsBuilder: () => {'path': trimmed},
      );
      return;
    }
    if (M3uPlaylist.isPlaylistPath(trimmed)) {
      await importPlaylistFile(trimmed, playNow: true, origin: origin);
      return;
    }
    await loadSource(
      PlayableSource.file(trimmed),
      forcePlay: forcePlay,
      origin: origin,
    );
  }

  Future<void> importPlaylistFile(
    String playlistPath, {
    required bool playNow,
    SourceOrigin origin = SourceOrigin.other,
  }) async {
    if (PlayerPathUtils.isUnsafeOpenPath(
      playlistPath,
      allowUnc: origin.allowsUnc,
    )) {
      _handleLoadValidationFailure(
        failure: SourceLoadValidationFailure.unsafePath,
        detailsBuilder: () => {'path': playlistPath},
      );
      return;
    }
    try {
      final sources = await M3uPlaylist.parseFile(playlistPath);
      if (sources.isEmpty) {
        if (isMounted()) {
          showMessage(l10n().snackPlaylistEmptyOrInvalid);
        }
        return;
      }
      pickers.rememberLastOpenDirectory(playlistPath);
      media.rememberRecentAndJumpList(playlistPath);
      enqueueSources(sources, playNow: playNow);
      log(
        'playlist_imported',
        detailsBuilder: () => {
          'path': playlistPath,
          'count': sources.length,
          'play_now': playNow,
        },
      );
    } catch (e) {
      log(
        'playlist_import_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (isMounted()) {
        showMessage(l10n().snackPlaylistImportFailed);
      }
    }
  }

  Future<void> loadSource(
    PlayableSource source, {
    bool forcePlay = false,
    bool syncPlaylist = true,
    bool applyResume = true,
    bool? playOverride,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    return playback.loadQueue.enqueue(
      () async {
        await _loadSourceInternal(
          source,
          forcePlay: forcePlay,
          syncPlaylist: syncPlaylist,
          applyResume: applyResume,
          playOverride: playOverride,
          origin: origin,
        );
      },
      onError: (Object e, StackTrace st) {
        log(
          'load_queue_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      },
    );
  }

  Future<bool> _loadSourceInternal(
    PlayableSource source, {
    bool forcePlay = false,
    bool syncPlaylist = true,
    bool applyResume = true,
    bool? playOverride,
    _LoadFailureBatch? failureBatch,
    SourceOrigin origin = SourceOrigin.other,
  }) async {
    if (isDisposed()) return false;
    final requestedValue = source.value.trim();
    final normalizedSource = source.isUrl
        ? PlayableSource.url(requestedValue)
        : PlayableSource.file(await _resolveSandboxedPath(requestedValue));
    final normalizedValue = normalizedSource.value;

    final fileExists =
        isHeadlessMedia() ||
        !normalizedSource.isFile ||
        await PathProbe.fileExists(normalizedValue);
    if (isDisposed()) return false;
    final validation = SourceLoadValidationPolicy.validateNormalizedOpen(
      source: source,
      trimmedValue: requestedValue,
      normalizedSource: normalizedSource,
      fileExists: fileExists,
      origin: origin,
    );
    if (!validation.isOk) {
      _handleLoadValidationFailure(
        failure: validation.failure,
        batch: failureBatch,
        detailsBuilder: () => switch (validation.failure) {
          SourceLoadValidationFailure.invalidUrl => {'url': requestedValue},
          SourceLoadValidationFailure.missingFile => {'path': normalizedValue},
          SourceLoadValidationFailure.unsafePath => {'path': requestedValue},
          _ => {'path': requestedValue, 'source': source.value},
        },
      );
      return false;
    }

    final priorQueue = syncPlaylist ? playlist.capture() : null;
    if (syncPlaylist) {
      playlist.setPlayingSource(normalizedSource);
    }
    final queueRevision = playlist.revision;
    void restoreQueue() {
      if (priorQueue == null) return;
      if (playlist.revision != queueRevision) return;
      playlist.restore(priorQueue);
    }

    final ext = normalizedSource.extension ?? '';
    log(
      'file_load_started',
      detailsBuilder: () => {
        'source': normalizedValue,
        'source_type': normalizedSource.type.name,
        'extension': ext,
      },
    );
    if (SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension(
      isFile: normalizedSource.isFile,
      ext: ext,
    )) {
      log(
        'file_load_unrecognized_extension',
        detailsBuilder: () => {'extension': ext, 'path': normalizedValue},
        severity: DebugSeverity.warn,
      );
      if (isMounted()) {
        showMessage(l10n().snackUnsupportedFileType);
      }
    }
    final gen = playback.beginLoad();
    media.resetArtForNewLoad();
    if (SourceLoadPreOpenPolicy.shouldAbortBeforeOpen(
      mounted: isMounted(),
      isDisposed: isDisposed(),
    )) {
      restoreQueue();
      return false;
    }
    persistResumePosition();
    playback.chapterGate.invalidate();
    update(() {
      player.beginSourceLoad(normalizedSource, ext);
      media.clearDisplayMetadata();
    });
    await advancedPlayback.setSource(normalizedSource);
    log(
      'media_type_initial_state',
      detailsBuilder: () => {
        'is_audio_file': player.isAudioFile,
        'has_video_output': false,
      },
    );

    try {
      player.fileOpenInProgress = true;
      tracks.resetMixLoadState();
      await playerService.setProperty('lavfi-complex', '');
      player.mixActive = false;
      final open = SourceOpenPolicy.paramsFor(
        normalizedPath: normalizedValue,
        forcePlay: forcePlay,
        autoPlaySetting: settings.autoPlay,
        playOverride: playOverride,
      );
      await playerService.open(
        open.path,
        play: open.play,
        allowUnc: origin.allowsUnc,
      );
      // Re-apply after open because libmpv may reset per-file properties.
      await advancedPlayback.applyForCurrentSource();
    } catch (e) {
      final failureKind = SourceLoadFailurePolicy.classify(e);
      final failureReaction = SourceLoadOpenPolicy.openFailureReaction(
        kind: failureKind,
        isLoadCurrent: playback.isLoadCurrent(gen),
        mounted: isMounted(),
      );
      log(
        SourceLoadFailurePolicy.logEvent(failureKind),
        message: e.toString(),
        detailsBuilder: () => {'source': normalizedValue},
        severity: failureReaction.logAsWarning
            ? DebugSeverity.warn
            : DebugSeverity.error,
      );
      restoreQueue();
      if (!failureReaction.shouldUpdateUi) return false;
      await advancedPlayback.setSource(null);
      if (!isMounted()) return false;
      update(player.clearSourceOnLoadFailure);
      unawaited(seekPreview.setSource(null));
      final failureMessage = PlayerMessenger.loadUserMessageText(
        l10n(),
        SourceLoadFailurePolicy.userMessage(failureKind),
      );
      if (failureBatch != null) {
        failureBatch.add(failureMessage);
      } else {
        showMessage(failureMessage);
      }
      return false;
    } finally {
      player.fileOpenInProgress = false;
    }

    if (_stopInProgress) return true;

    final postOpen = SourceLoadPostOpenPolicy.plan(
      isLoadCurrent: playback.isLoadCurrent(gen),
      isDisposed: isDisposed(),
      mounted: isMounted(),
      normalizedSource: normalizedSource,
      isAudioFile: player.isAudioFile,
    );
    final followUp = SourceLoadPostOpenPolicy.followUpFor(postOpen);
    if (!postOpen.shouldProceed) {
      return true;
    }
    tracks.cacheTracksForCurrentLoad(playerService.currentTracks, gen: gen);

    if (followUp.shouldClearSeekPreview) {
      unawaited(seekPreview.setSource(null));
    } else if (followUp.seekPreviewPath != null) {
      unawaited(seekPreview.setSource(followUp.seekPreviewPath));
    }

    log(
      'file_load_succeeded',
      detailsBuilder: () => {
        'source': normalizedValue,
        'source_type': normalizedSource.type.name,
        'auto_play': settings.autoPlay,
      },
    );

    try {
      if (followUp.shouldPersistRecent) {
        media.rememberRecentAndJumpList(normalizedValue);
      }
      if (followUp.shouldRememberOpenDirectory) {
        pickers.rememberLastOpenDirectory(normalizedValue);
      }
      log(
        followUp.recentPersistLogEvent,
        category: DebugLogCategory.settings,
        detailsBuilder: () => {'source': normalizedValue},
      );
    } catch (e) {
      log(
        'recent_file_persist_failed',
        category: DebugLogCategory.settings,
        message: e.toString(),
        detailsBuilder: () => {'source': normalizedValue},
        severity: DebugSeverity.warn,
      );
    }

    if (followUp.shouldRefreshUi) {
      update(() {});
    }

    player.resumePathInProgress = followUp.resumeTrackingPath;
    await tracks.applyMergedAudioFilters(gen: gen);
    await tracks.refreshChapters(gen: gen);
    await tracks.applyMultiAudioMix(gen: gen);
    if (followUp.shouldApplyResume && applyResume) {
      await _maybeApplyResume(normalizedValue, gen: gen);
    }
    unawaited(media.refreshMetadata(normalizedSource, gen: gen));
    return true;
  }

  void applyDroppedPaths(
    Iterable<String> rawPaths, {
    required SourceOrigin origin,
  }) {
    final batch = DropPathBatchPolicy.fromRawPaths(
      rawPaths: rawPaths,
      windows: Platform.isWindows,
      allowUnc: origin.allowsUnc,
    );
    if (batch.isEmpty) {
      log(
        'drop_file_invalid_path',
        detailsBuilder: () => {'count': rawPaths.length},
        severity: DebugSeverity.warn,
      );
      if (isMounted()) {
        showMessage(l10n().snackCouldNotReadDroppedFile);
      }
      return;
    }
    log(
      'drop_file_received',
      detailsBuilder: () => {
        'path': batch.paths.first,
        'count': batch.paths.length,
        'skipped': batch.skippedCount,
      },
    );
    if (batch.skippedCount > 0 && isMounted()) {
      final l10n = this.l10n();
      showMessage(
        batch.skippedCount == 1
            ? l10n.snackSkippedUnreadableFile
            : l10n.snackSkippedUnreadableFiles(batch.skippedCount),
      );
    }
    unawaited(_applyDroppedPathsExpanded(batch.paths, origin: origin));
  }

  Future<void> _applyDroppedPathsExpanded(
    List<String> paths, {
    required SourceOrigin origin,
  }) async {
    final media = <PlayableSource>[];
    var inaccessible = 0;
    for (final path in paths) {
      if (PlayableSource.isSupportedUrl(path)) {
        media.add(PlayableSource.url(path));
        continue;
      }
      await captureBookmarkFor(path);
      try {
        if (await PathProbe.directoryExists(path)) {
          final scan = await MediaFolderScanner.scan(
            path,
            maxItems: PlaylistService.maxQueueItems,
          );
          media.addAll(scan.paths.map(PlayableSource.file));
          continue;
        }
      } catch (_) {
        // Fall through to file handling.
      }
      if (M3uPlaylist.isPlaylistPath(path)) {
        try {
          media.addAll(await M3uPlaylist.parseFile(path));
        } catch (e) {
          log(
            'drop_playlist_parse_failed',
            message: e.toString(),
            detailsBuilder: () => {'path': path},
            severity: DebugSeverity.warn,
          );
        }
        continue;
      }
      if (!isHeadlessMedia()) {
        try {
          if (!await PathProbe.fileExists(path)) {
            inaccessible++;
            continue;
          }
        } catch (_) {
          inaccessible++;
          continue;
        }
      }
      media.add(PlayableSource.file(path));
    }
    if (inaccessible > 0 && isMounted()) {
      showMessage(l10n().snackDropPathInaccessible);
    }
    if (media.isEmpty) {
      if (isMounted()) {
        showMessage(l10n().snackPlaylistEmptyOrInvalid);
      }
      return;
    }
    switch (DropFilePolicy.action(validPathCount: media.length)) {
      case DropFileAction.none:
        return;
      case DropFileAction.loadSingle:
        final only = media.first;
        if (only.isFile) {
          unawaited(_loadFile(only.value, origin: origin));
        } else {
          unawaited(loadSource(only, origin: origin));
        }
      case DropFileAction.enqueuePlayNow:
        enqueueSources(media, playNow: true, origin: origin);
    }
  }

  // ── Resume position ─────────────────────────────────

  void persistResumePosition({bool requirePlaying = false}) {
    if (!settings.resumePlaybackEnabled) return;
    if (requirePlaying && !player.isPlaying) return;
    final path = player.resumePathInProgress;
    if (path == null) return;
    final action = ResumePlaybackPolicy.persistAction(
      position: player.position,
      duration: player.duration,
    );
    switch (action) {
      case ResumePersistAction.skip:
        return;
      case ResumePersistAction.clear:
        settings.saveResumePosition(path, null);
      case ResumePersistAction.save:
        settings.saveResumePosition(path, player.position.inMilliseconds);
    }
  }

  Future<void> _maybeApplyResume(String path, {int? gen}) async {
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final l10n = this.l10n();
    final ms = settings.resumePositionFor(path);
    var action = ResumePlaybackPolicy.applyAction(
      resumeMs: ms,
      durationMs: player.duration.inMilliseconds,
    );
    for (
      var i = 0;
      i < ResumePlaybackPolicy.durationPollAttempts &&
          action == ResumeApplyAction.waitForDuration;
      i++
    ) {
      await Future<void>.delayed(_durationPollInterval);
      if (isDisposed() ||
          player.currentFile != path ||
          (gen != null && !playback.isLoadCurrent(gen))) {
        return;
      }
      action = ResumePlaybackPolicy.applyAction(
        resumeMs: ms,
        durationMs: player.duration.inMilliseconds,
      );
    }
    switch (action) {
      case ResumeApplyAction.skip:
      case ResumeApplyAction.waitForDuration:
        return;
      case ResumeApplyAction.clearStored:
        settings.saveResumePosition(path, null);
        return;
      case ResumeApplyAction.seek:
        break;
    }
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    try {
      await playerService.seek(Duration(milliseconds: ms!));
      if (isMounted() && (gen == null || playback.isLoadCurrent(gen))) {
        showOsd(
          l10n.osdResumedAt(
            ResumePlaybackPolicy.formatHms(Duration(milliseconds: ms)),
          ),
        );
      }
    } catch (e) {
      log(
        'resume_seek_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<void> stopPlaybackAndResetUi() async {
    _stopInProgress = true;
    playback.beginLoad();
    try {
      await playback.loadQueue.enqueue(
        () async {
          if (isDisposed()) return;
          playback.beginLoad();
          persistResumePosition();
          await playerService.setProperty('lavfi-complex', '');
          player.mixActive = false;
          await playerService.stop();
          await advancedPlayback.setSource(null);
          unawaited(seekPreview.setSource(null));
          media.clearSession();
          if (!isMounted() || isDisposed()) return;
          update(() {
            player.clearMediaSurface();
            media.clearDisplayMetadata();
          });
        },
        onError: (Object e, StackTrace st) {
          log(
            'stop_queue_failed',
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        },
      );
    } finally {
      _stopInProgress = false;
    }
  }

  // ── Playlist ────────────────────────────────────────

  Future<void> advancePlaylist(int delta) async {
    if (playlist.isEmpty) return;
    await playback.loadQueue.enqueue(
      () async {
        if (isDisposed() || playlist.isEmpty) return;
        final wrap = PlaylistAdvancePolicy.shouldWrapQueue(settings.loopMode);
        final next = playlist.advance(delta, wrap: wrap);
        if (next == null) return;
        final l10n = this.l10n();
        showOsd(delta > 0 ? l10n.osdNextInQueue : l10n.osdPreviousInQueue);
        await _loadSourceInternal(
          next,
          syncPlaylist: false,
          origin: SourceOrigin.queue,
        );
      },
      onError: (Object e, StackTrace st) {
        log(
          'load_queue_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      },
    );
  }

  void enqueue(
    List<String> paths, {
    bool playNow = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    enqueueSources(
      paths.map(PlayableSource.file).toList(growable: false),
      playNow: playNow,
      origin: origin,
    );
  }

  void enqueueSources(
    List<PlayableSource> sources, {
    bool playNow = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    if (sources.isEmpty) return;
    switch (EnqueuePolicy.mode(
      playNow: playNow,
      playlistEmpty: playlist.isEmpty,
    )) {
      case EnqueueMode.replaceAndPlay:
        final candidates = sources
            .where((source) => source.value.trim().isNotEmpty)
            .toList(growable: false);
        final attemptLimit = math.min(
          candidates.length,
          PlaylistService.maxQueueItems,
        );
        unawaited(
          playback.loadQueue.enqueue(() async {
            var openedIndex = -1;
            final failureBatch = candidates.length > 1
                ? _LoadFailureBatch()
                : null;
            try {
              for (var i = 0; i < attemptLimit; i++) {
                if (isDisposed()) return;
                if (await _loadSourceInternal(
                  candidates[i],
                  syncPlaylist: false,
                  failureBatch: failureBatch,
                  origin: origin,
                )) {
                  openedIndex = i;
                  break;
                }
              }
            } finally {
              if (failureBatch != null) _flushLoadFailureBatch(failureBatch);
            }
            if (openedIndex < 0 || isDisposed()) return;
            final dropped = playlist.replaceSources(
              candidates,
              startIndex: openedIndex,
            );
            if (dropped > 0 && isMounted()) {
              showMessage(
                l10n().snackQueueTruncated(
                  PlaylistService.maxQueueItems,
                  dropped,
                ),
              );
            }
          }),
        );
      case EnqueueMode.append:
        final dropped = playlist.addAllSources(sources);
        showOsd(
          sources.length == 1
              ? l10n().osdAddedToQueue
              : l10n().osdAddedMultipleToQueue(sources.length),
        );
        if (dropped > 0 && isMounted()) {
          showMessage(
            l10n().snackQueueTruncated(PlaylistService.maxQueueItems, dropped),
          );
        }
    }
  }
}

class _LoadFailureBatch {
  int count = 0;
  bool pruneRecents = false;
  String? firstMessage;

  void add(String message) {
    count++;
    firstMessage ??= message;
  }
}
