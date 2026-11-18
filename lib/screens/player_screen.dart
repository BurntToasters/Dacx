import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../services/player_service.dart';
import '../services/advanced_playback_controller.dart';
import '../services/app_exit_hooks.dart';
import '../services/player_shortcuts_service.dart';
import '../services/instance_mode_service.dart';
import '../services/settings_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/idle_inhibit_service.dart';
import '../services/debug_log_service.dart';
import '../services/media_session_service.dart';
import '../services/packaged_e2e_probe.dart';
import '../services/playlist_service.dart';
import '../services/bookmark_service.dart';
import '../services/open_file_bridge.dart';
import '../services/path_probe.dart';
import '../services/seek_preview_service.dart';
import '../services/self_update_service.dart';
import '../services/windows_shell_service.dart';
import '../models/chapter_info.dart';
import '../models/playable_source.dart';
import '../l10n/app_localizations.dart';
import '../theme/glass_decorations.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../playback/chapter_list_loader.dart';
import '../playback/media_folder_scanner.dart';
import '../playback/playback_controller.dart';
import '../playback/playback_mix_policy.dart';
import '../playback/media_session_command_dispatch.dart';
import '../playback/player_path_utils.dart';
import '../playback/player_audio_session.dart';
import '../playback/player_controller.dart';
import '../playback/sleep_timer_controller.dart';
import '../playback/player_settings_sync.dart';
import '../playback/chapter_navigation_policy.dart';
import '../playback/drop_path_batch_policy.dart';
import '../playback/enqueue_policy.dart';
import '../playback/file_picker_path.dart';
import '../playback/linux_install_kind.dart';
import '../playback/m3u_playlist.dart';
import '../playback/playback_speed_policy.dart';
import '../playback/resume_playback_policy.dart';
import '../playback/screenshot_saver.dart';
import '../playback/source_load_post_open_policy.dart';
import '../playback/source_load_pre_open_policy.dart';
import '../playback/source_load_open_policy.dart';
import '../playback/playlist_advance_policy.dart';
import '../playback/track_cycle_policy.dart';
import '../playback/source_load_validation_policy.dart';
import '../playback/source_open_policy.dart';
import '../playback/volume_policy.dart';
import '../playback/track_label.dart';
import '../playback/update_launch_policy.dart';
import '../playback/subscription_bag.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/dialog_sizing.dart';
import '../widgets/equalizer_dialog.dart';
import '../widgets/keybinds_dialog.dart';
import '../widgets/manual_update_check.dart';
import '../widgets/media_info_dialog.dart';
import '../widgets/update_progress_dialog.dart';
import '../widgets/track_pickers.dart';
import '../widgets/advanced_playback_dialog.dart';
import 'player/player_file_pickers.dart';
import 'player/player_messenger.dart';
import 'player/widgets/drag_overlay.dart';
import 'player/widgets/media_surface.dart';
import 'player/widgets/player_bottom_dock.dart';
import 'player/widgets/play_queue_drawer.dart';
import 'player/widgets/player_more_menu.dart';
import 'settings_screen.dart';

const _resumeSaveInterval = Duration(seconds: 5);
const _seekStep = Duration(seconds: 5);
const _seekStepBack = Duration(seconds: -5);
const _updateSnackbarDuration = Duration(seconds: 10);
const _snackbarShortDuration = Duration(seconds: 2);
const _settingsFwdTransition = Duration(milliseconds: 340);
const _settingsRevTransition = Duration(milliseconds: 280);
const _mixReloadDelay = Duration(milliseconds: 200);
const _durationPollInterval = Duration(milliseconds: 50);

class PlayerScreen extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final UpdateService updateService;
  final String? initialFile;
  final IPlayerService? playerService;
  final VideoController? videoController;
  final bool headlessMediaSurface;
  final PlayableSource? initialLoadedSource;
  final List<PlayableSource>? initialPlaylistSources;
  final List<ChapterInfo>? initialChapters;
  final List<String>? initialDropPaths;
  final PlayableSource? initialPendingLoad;
  final ValueNotifier<String?>? osdMessageProbe;
  final Completer<void>? screenshotOperationForTesting;
  final StreamController<MediaSessionCommand>? mediaSessionCommandsForTesting;
  final Future<void> Function()? onQuitRequest;
  final ValueChanged<bool>? onCompactModeChanged;

  const PlayerScreen({
    super.key,
    required this.settings,
    required this.debugLog,
    required this.updateService,
    this.initialFile,
    @visibleForTesting this.playerService,
    @visibleForTesting this.videoController,
    @visibleForTesting this.headlessMediaSurface = false,
    @visibleForTesting this.initialLoadedSource,
    @visibleForTesting this.initialPlaylistSources,
    @visibleForTesting this.initialChapters,
    @visibleForTesting this.initialDropPaths,
    @visibleForTesting this.initialPendingLoad,
    @visibleForTesting this.osdMessageProbe,
    @visibleForTesting this.screenshotOperationForTesting,
    @visibleForTesting this.mediaSessionCommandsForTesting,
    this.onQuitRequest,
    this.onCompactModeChanged,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _shortcutFocus = FocusNode(
    debugLabel: 'player-shortcuts',
    skipTraversal: true,
  );
  late final IPlayerService _playerService;
  late final AdvancedPlaybackController _advancedPlayback;
  PackagedE2eProbe? _packagedE2eProbe;
  VideoController? _videoController;
  late final SeekPreviewService _seekPreviewService;
  late final PlayerAudioSession _audioSession;
  late final PlaybackController _playback;
  late final SleepTimerController _sleepTimer;
  final _subscriptions = SubscriptionBag();
  UpdateService get _updateService => widget.updateService;

  SettingsService get _settings => widget.settings;

  final _player = PlayerController();
  String? get _currentFile => _player.currentFile;
  bool _isDragging = false;
  final _mixLoadState = PlaybackMixLoadState();
  bool _mixReloadInFlight = false;
  PlayerSettingsSyncState _settingsSyncState = const PlayerSettingsSyncState();

  bool _isDisposed = false;
  bool _stopInProgress = false;
  Timer? _fullscreenChromeHideTimer;
  final _scrollVolume = ScrollVolumeAccumulator();
  bool _fullscreenChromeVisible = true;

  // Tracks / chapters / OSD state
  late final PlayerFilePickers _pickers = PlayerFilePickers(
    settings: _settings,
    restoreFocus: _restoreShortcutFocus,
  );
  late final PlayerMessenger _messenger = PlayerMessenger(
    player: _player,
    osdEnabled: () => _settings.osdEnabled,
    isMounted: () => mounted,
    update: setState,
    osdMessageProbe: widget.osdMessageProbe,
  );
  late final MediaSessionService _mediaSession;
  late final PlaylistService _playlist;
  late final OpenFileBridge _openFileBridge;
  final _idleInhibit = IdleInhibitService();

  // Compact mini-player mode (PiP-style on desktop).
  bool _compactMode = false;
  bool _compactToggleInFlight = false;
  Size? _preCompactSize;
  Offset? _preCompactPos;
  bool _preCompactMaximized = false;
  static const Size _compactWindowSize = Size(480, 320);

  // Resume-position bookkeeping.
  Timer? _resumeSaveTimer;
  Timer? _updateCheckTimer;

  String? _activeBookmarkToken;
  String? _mediaDisplayTitle;
  String? _mediaDisplayArtist;
  int _mediaSessionArtExportGen = 0;
  String? _lastMediaSessionArtUri;

  void _log(
    String event, {
    DebugLogCategory category = DebugLogCategory.playback,
    String? message,
    Map<String, Object?> details = const {},
    String? Function()? messageBuilder,
    Map<String, Object?> Function()? detailsBuilder,
    DebugSeverity severity = DebugSeverity.info,
  }) {
    if (!widget.debugLog.isEnabled) return;
    widget.debugLog.logLazy(
      category: category,
      event: event,
      messageBuilder:
          messageBuilder ?? (message == null ? null : () => message),
      detailsBuilder:
          detailsBuilder ?? (details.isEmpty ? null : () => details),
      severity: severity,
    );
  }

  String _loadUserMessageText(SourceLoadUserMessageKind kind) =>
      PlayerMessenger.loadUserMessageText(AppLocalizations.of(context), kind);

  void _handleLoadValidationFailure({
    required SourceLoadValidationFailure failure,
    required Map<String, Object?> Function() detailsBuilder,
    _LoadFailureBatch? batch,
  }) {
    final reaction = SourceLoadValidationPolicy.reactionFor(failure);
    if (reaction.logEvent.isNotEmpty) {
      _log(
        reaction.logEvent,
        detailsBuilder: detailsBuilder,
        severity: DebugSeverity.warn,
      );
    }
    if (reaction.shouldPruneRecentFiles) {
      if (batch != null) {
        batch.pruneRecents = true;
      } else {
        unawaited(_settings.pruneRecentFiles());
      }
    }
    if (!mounted || reaction.userMessage == null) return;
    final message = _loadUserMessageText(reaction.userMessage!);
    if (batch != null) {
      batch.add(message);
      return;
    }
    showAppSnackBar(context, message);
  }

  void _flushLoadFailureBatch(_LoadFailureBatch batch) {
    if (batch.pruneRecents) {
      unawaited(_settings.pruneRecentFiles());
    }
    if (!mounted || batch.count == 0) return;
    final message = batch.count == 1
        ? batch.firstMessage!
        : AppLocalizations.of(context).snackLoadFailuresSummary(batch.count);
    showAppSnackBar(context, message);
  }

  bool get _headlessMedia =>
      widget.headlessMediaSurface ||
      (widget.playerService != null && widget.videoController == null);

  @override
  void initState() {
    super.initState();
    _playback = PlaybackController();
    _playerService = widget.playerService ?? PlayerService();
    _advancedPlayback = AdvancedPlaybackController(
      settings: _settings,
      player: _playerService,
    );
    _seekPreviewService = SeekPreviewService();
    _audioSession = PlayerAudioSession(
      playerService: _playerService,
      settings: _settings,
      player: _player,
    );
    _sleepTimer = SleepTimerController(onFire: _onSleepTimerFired);
    unawaited(_seekPreviewService.setEnabled(_settings.seekPreviewEnabled));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      unawaited(() async {
        await _settings.pruneRecentFiles(notifyListeners: false);
        if (_isDisposed) return;
        await _syncWindowsJumpList();
      }());
    });
    final hwDec = _settings.hwDec;
    final hwEnabled = _shouldEnableHardwareAcceleration(hwDec);
    final hwReason = HardwareAccelerationService.debugStatusReason(hwDec);
    _log(
      'video_controller_configured',
      category: DebugLogCategory.hwaccel,
      detailsBuilder: () => {
        'hwdec': hwDec,
        'enabled': hwEnabled,
        'reason': hwReason,
      },
    );
    _videoController = widget.videoController;
    if (_videoController == null && !_headlessMedia) {
      final native = _playerService;
      if (native is PlayerService) {
        _videoController = VideoController(
          native.player,
          configuration: VideoControllerConfiguration(
            hwdec: hwDec,
            enableHardwareAcceleration: hwEnabled,
          ),
        );
      }
    }
    _mediaSession = MediaSessionService(debugLog: widget.debugLog);
    unawaited(
      _mediaSession.init(enabled: _settings.mediaSessionEnabled).catchError((
        Object e,
      ) {
        _log(
          'media_session_init_failed',
          category: DebugLogCategory.system,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _playlist = PlaylistService()..setShuffle(_settings.playlistShuffle);
    _player.volume = _settings.volume;
    _settingsSyncState = PlayerSettingsSyncState(
      lastSpeed: _settings.speed,
      lastLoopMode: _settings.loopMode,
      lastAlwaysOnTop: _settings.alwaysOnTop,
      lastMediaSessionEnabled: _settings.mediaSessionEnabled,
      lastPlaylistShuffle: _settings.playlistShuffle,
      lastHwDec: _settings.hwDec,
      lastMultiAudioMix: _settings.multiAudioMix,
      lastEqEnabled: _settings.eqEnabled,
      lastEqBands: List<double>.from(_settings.eqBands),
    );
    _log(
      'player_init',
      detailsBuilder: () => {
        'auto_play': _settings.autoPlay,
        'volume': _player.volume.toStringAsFixed(2),
        'speed': _settings.speed.toStringAsFixed(2),
        'loop_mode': _settings.loopMode.name,
      },
    );

    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onGlobalShortcutKey);

    // Apply saved playback settings.
    unawaited(
      _playerService.setVolume(_player.volume).catchError((Object e) {
        _log(
          'initial_volume_apply_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _applySpeed(_settings.speed);
    _applyLoopMode(_settings.loopMode);
    _applyHwDec(_settings.hwDec);

    final streamSubs = <StreamSubscription>[
      _playerService.positionStream.listen((pos) {
        if (!mounted || _isDisposed) return;
        _advancedPlayback.setPosition(pos);
        final update = _player.onPosition(pos);
        if (update == PositionUiUpdate.skip) return;
        if (update == PositionUiUpdate.notify) {
          setState(() {});
        }
        if (_settings.mediaSessionEnabled) {
          _maybeUpdateMediaSessionPosition(pos);
        }
        _maybeUpdateTaskbarProgress(pos);
      }),
      _playerService.durationStream.listen((dur) {
        if (!mounted || _isDisposed) return;
        final packagedProbe = _packagedE2eProbe;
        if (packagedProbe != null) {
          unawaited(packagedProbe.recordDuration(dur));
        }
        _advancedPlayback.setDuration(dur);
        setState(() => _player.duration = dur);
        if (dur.inMilliseconds > 0 && _settings.mediaSessionEnabled) {
          final source = _player.currentSource;
          if (source != null) {
            unawaited(
              _refreshMediaMetadata(source, duration: dur, exportArt: false),
            );
          }
        }
        if (dur.inMilliseconds > 0 && widget.debugLog.isEnabled) {
          _log(
            'duration_updated',
            detailsBuilder: () => {'duration_ms': dur.inMilliseconds},
          );
        }
      }),
      _playerService.playingStream.listen((playing) {
        if (!mounted || _isDisposed) return;
        final packagedProbe = _packagedE2eProbe;
        if (packagedProbe != null) {
          unawaited(packagedProbe.recordPlaying(playing));
        }
        setState(() => _player.isPlaying = playing);
        // Save on pause: the periodic saver only runs while playing, so a
        // pause (and any seek after it) would otherwise not be stored.
        if (!playing && !_player.fileOpenInProgress) {
          _persistResumePosition();
        }
        _syncIdleInhibit();
        if (!playing) {
          unawaited(WindowsShellService.clearTaskbarProgress());
        }
        if (_settings.mediaSessionEnabled) {
          _maybeUpdateMediaSessionPosition(_player.position);
        }
        if (widget.debugLog.isEnabled) {
          _log(
            'playing_state_changed',
            detailsBuilder: () => {'playing': playing},
          );
        }
      }),
      _playerService.volumeStream.listen((vol) {
        if (!mounted || _isDisposed) return;
        setState(() => _player.volume = vol);
        unawaited(_mediaSession.updateVolume((vol / 100.0).clamp(0.0, 1.0)));
        if (widget.debugLog.isEnabled) {
          _log(
            'volume_stream_updated',
            detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
          );
        }
      }),
      _playerService.videoWidthStream.listen((w) {
        if (!mounted || _isDisposed) return;
        if (_player.onVideoWidth(w)) {
          setState(() {});
          _syncIdleInhibit();
          if (widget.debugLog.isEnabled) {
            _log(
              'video_output_changed',
              detailsBuilder: () => {
                'has_video_output': _player.hasVideoOutput,
                'width': w,
              },
            );
          }
        }
      }),
      _playerService.tracksStream.listen((tracks) {
        if (!mounted || _isDisposed) return;
        _onAlbumArtTracks(tracks);
        if (_stopInProgress || _player.fileOpenInProgress) return;
        _cacheTracksForCurrentLoad(
          tracks,
          refreshChapters: true,
          gen: _playback.loadGeneration,
        );
      }),
      _playerService.errorStream.listen((event) {
        if (!mounted || _isDisposed) return;
        _packagedE2eProbe?.recordError(event);
        _log(
          'player_operation_failed',
          message: event.toString(),
          severity: DebugSeverity.warn,
        );
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          final l10n = AppLocalizations.of(context);
          messenger.showAppSnackBar(
            l10n.snackPlaybackOperationFailed(event.error.toString()),
            duration: const Duration(seconds: 4),
          );
        }
      }),
      _playerService.completedStream.listen((completed) {
        if (!mounted || _isDisposed || !completed) return;
        if (_stopInProgress || _playback.loadQueue.isBusy) return;
        if (_player.currentSource == null) return;
        setState(() => _player.position = Duration.zero);
        if (widget.debugLog.isEnabled) {
          _log('playback_completed');
        }
        // File ran to end → drop saved resume position.
        final source = _player.currentSource;
        if (source != null && source.isFile) {
          _settings.saveResumePosition(source.value, null);
        }
        // Try to advance the playlist for queue-driven loop modes.
        if (PlaylistAdvancePolicy.shouldAdvanceOnCompleted(
          _settings.loopMode,
        )) {
          unawaited(_advancePlaylist(1));
        }
      }),
      _playerService.trackStream.listen((track) {
        if (!mounted || _isDisposed) return;
        _player.currentTrackSelection = track;
      }),
    ];
    for (final sub in streamSubs) {
      _subscriptions.add(sub);
    }
    unawaited(_initializePackagedE2eProbe());
    _subscriptions.add(_mediaSession.commands.listen(_onMediaSessionCommand));
    final testCommandStream = widget.mediaSessionCommandsForTesting?.stream;
    if (testCommandStream != null) {
      _subscriptions.add(testCommandStream.listen(_onMediaSessionCommand));
    }

    // Periodic resume-position saver (every 5s while playing).
    _resumeSaveTimer = Timer.periodic(
      _resumeSaveInterval,
      (_) => _persistResumePosition(requirePlaying: true),
    );

    _checkForUpdates();
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (!_isDisposed && mounted) _checkForUpdates();
    });

    _openFileBridge = OpenFileBridge(
      onOpenRequest: _openRequestedFileRequest,
      onOpenBatch: _openRequestedFileBatch,
      isActive: () => !_isDisposed && mounted,
      onLog:
          (event, {message, details = const {}, warn = false, error = false}) {
            _log(
              event,
              category: DebugLogCategory.system,
              message: message,
              details: details,
              severity: error
                  ? DebugSeverity.error
                  : (warn ? DebugSeverity.warn : DebugSeverity.info),
            );
          },
    );

    AppExitHooks.add(_saveStateBeforeExit);

    // Listen for settings changes (speed, loop, always-on-top).
    _settings.addListener(_onSettingsChanged);
    _initializePlatformFileOpenBridge();
    _initializeMacAppMenuBridge();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showPendingUpdateNotice());
    });

    if (widget.initialFile != null) {
      _log(
        'initial_file_requested',
        detailsBuilder: () => {'path': widget.initialFile},
      );
    }

    final seededSource = widget.initialLoadedSource;
    if (seededSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        setState(
          () => _player.beginSourceLoad(
            seededSource,
            seededSource.extension ?? '',
          ),
        );
        unawaited(_advancedPlayback.setSource(seededSource));
      });
    }

    final seededPlaylist = widget.initialPlaylistSources;
    if (seededPlaylist != null && seededPlaylist.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _playlist.replaceSources(seededPlaylist);
      });
    }

    final seededChapters = widget.initialChapters;
    if (seededChapters != null && seededChapters.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        setState(() => _player.chapters = seededChapters);
      });
    }

    final seededDropPaths = widget.initialDropPaths;
    if (seededDropPaths != null && seededDropPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _applyDroppedPaths(seededDropPaths, origin: SourceOrigin.dragDrop);
      });
    }

    final pendingLoad = widget.initialPendingLoad;
    if (pendingLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        unawaited(_loadSource(pendingLoad));
      });
    }
  }

  void _onAlbumArtTracks(Tracks tracks) {
    final artChange = _player.onTracksStream(tracks);
    if (artChange.uiChanged) {
      setState(() {});
      _log(
        'album_art_track_changed',
        detailsBuilder: () => {
          'has_album_art_track': artChange.hasAlbumArt,
          'track_id': artChange.trackId,
        },
      );
    }

    if (!_player.isAudioFile || !artChange.uiChanged) return;

    final albumArtTrack = PlayerController.firstEmbeddedAlbumArtTrack(tracks);
    if (albumArtTrack != null) {
      final gen = _playback.loadGeneration;
      unawaited(
        _playerService
            .setVideoTrack(albumArtTrack)
            .then((_) async {
              // Let the album-art track settle before exporting for OS chrome.
              await Future<void>.delayed(const Duration(milliseconds: 120));
              if (!mounted || _isDisposed || !_playback.isLoadCurrent(gen)) {
                return;
              }
              final source = _player.currentSource;
              if (source != null && _settings.mediaSessionEnabled) {
                unawaited(_refreshMediaMetadata(source));
              }
            })
            .catchError((Object e) {
              _log(
                'album_art_track_select_failed',
                message: e.toString(),
                severity: DebugSeverity.warn,
              );
            }),
      );
    }
  }

  Future<void> _initializePackagedE2eProbe() async {
    final probe = await PackagedE2eProbe.fromEnvironment(
      player: _playerService,
    );
    if (!mounted || _isDisposed || probe == null) return;
    _packagedE2eProbe = probe;
    await probe.recordDuration(_player.duration);
    await probe.recordPlaying(_player.isPlaying);
  }

  /// Exit hook: window close, tray Quit, and Cmd+Q skip [dispose].
  Future<void> _saveStateBeforeExit() async {
    if (_isDisposed) return;
    _persistResumePosition();
    await _settings.flushResumePositions();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_compactMode) {
      widget.onCompactModeChanged?.call(false);
    }
    AppExitHooks.remove(_saveStateBeforeExit);
    HardwareKeyboard.instance.removeHandler(_onGlobalShortcutKey);
    _shortcutFocus.dispose();
    windowManager.removeListener(this);
    if (Platform.isMacOS) {
      const MethodChannel(InstanceModeService.windowMethodChannelName)
          .setMethodCallHandler(null);
    }
    _messenger.dispose();
    _fullscreenChromeHideTimer?.cancel();
    _resumeSaveTimer?.cancel();
    _updateCheckTimer?.cancel();
    _persistResumePosition();
    _log('player_dispose');
    _settings.removeListener(_onSettingsChanged);
    _openFileBridge.dispose();
    _subscriptions.cancelAll();
    _sleepTimer.dispose();
    _advancedPlayback.dispose();
    _playback.dispose();
    _player.dispose();
    _releaseActiveBookmark();
    unawaited(_mediaSession.dispose());
    _playlist.dispose();
    unawaited(_idleInhibit.dispose());
    unawaited(_seekPreviewService.dispose());
    unawaited(_playerService.dispose());
    super.dispose();
  }

  void _onSleepTimerFired() {
    if (!mounted || _isDisposed) return;
    unawaited(() async {
      await _stopPlaybackAndResetUi();
      if (!mounted || _isDisposed) return;
      showAppSnackBar(
        context,
        AppLocalizations.of(context).snackSleepTimerFired,
        duration: _snackbarShortDuration,
      );
    }());
  }

  void _setSleepTimerMinutes(int? minutes) {
    final l10n = AppLocalizations.of(context);
    if (minutes == null) {
      final wasActive = _sleepTimer.isActive;
      _sleepTimer.cancel();
      if (!wasActive || !mounted) return;
      showAppSnackBar(
        context,
        l10n.snackSleepTimerCancelled,
        duration: _snackbarShortDuration,
      );
      return;
    }
    _sleepTimer.startMinutes(minutes);
    if (!mounted) return;
    showAppSnackBar(
      context,
      l10n.snackSleepTimerSet(minutes),
      duration: _snackbarShortDuration,
    );
  }

  void _releaseActiveBookmark() {
    final token = _activeBookmarkToken;
    if (token == null || token.isEmpty) return;
    _activeBookmarkToken = null;
    unawaited(BookmarkService.stop(token));
  }

  Future<String> _resolveSandboxedPath(String requestedPath) async {
    final scoped = await _resolveBookmarkScope(requestedPath);
    if (scoped.token != null) {
      _releaseActiveBookmark();
      _activeBookmarkToken = scoped.token!.isNotEmpty ? scoped.token : null;
    }
    return scoped.path;
  }

  Future<({String path, String? token})> _resolveBookmarkScope(
    String requestedPath,
  ) async {
    if (!BookmarkService.isSupported) return (path: requestedPath, token: null);
    final coveringKey = _settings.coveringBookmarkKey(requestedPath);
    final bookmarkKey = coveringKey ?? requestedPath;
    final bookmark = _settings.fileBookmark(bookmarkKey);
    if (bookmark == null || bookmark.isEmpty) {
      return (path: requestedPath, token: null);
    }
    final resolved = await BookmarkService.resolveAndStart(bookmark);
    if (resolved == null) {
      // A covering folder bookmark may still be valid for siblings.
      if (coveringKey == null || coveringKey == requestedPath) {
        _settings.removeFileBookmark(requestedPath);
      }
      return (path: requestedPath, token: null);
    }
    final bookmarkToPersist = resolved.refreshed ?? bookmark;
    if (resolved.path != bookmarkKey) {
      _settings.setFileBookmark(resolved.path, bookmarkToPersist);
    } else if (resolved.stale && resolved.refreshed != null) {
      _settings.setFileBookmark(bookmarkKey, resolved.refreshed!);
    }
    if (coveringKey != null && coveringKey != requestedPath) {
      return (path: requestedPath, token: resolved.token);
    }
    return (path: resolved.path, token: resolved.token);
  }

  Future<void> _captureBookmarkFor(String path) async {
    if (!BookmarkService.isSupported) return;
    final bookmark = await BookmarkService.createBookmark(path);
    if (bookmark != null && bookmark.isNotEmpty) {
      _settings.setFileBookmark(path, bookmark);
    }
  }

  void _onSettingsChanged() {
    unawaited(
      _advancedPlayback.setEnabled(_settings.advancedPlaybackToolsEnabled),
    );
    _log(
      'settings_applied_to_player',
      category: DebugLogCategory.settings,
      detailsBuilder: () => {
        'speed': _settings.speed.toStringAsFixed(2),
        'loop_mode': _settings.loopMode.name,
        'always_on_top': _settings.alwaysOnTop,
        'hwdec': _settings.hwDec,
      },
    );

    final (delta, nextState) = PlayerSettingsSync.diff(
      state: _settingsSyncState,
      settings: _settings,
    );
    _settingsSyncState = nextState;

    if (delta.speed != null) {
      _applySpeed(delta.speed!);
      unawaited(_mediaSession.updateRate(delta.speed!));
    }

    if (delta.loopMode != null) {
      _applyLoopMode(delta.loopMode!);
      unawaited(
        _mediaSession.updateLoop(switch (delta.loopMode!) {
          LoopMode.none => 'none',
          LoopMode.single => 'single',
          LoopMode.loop => 'loop',
        }),
      );
    }

    final settingsVolume = _settings.volume;
    if ((settingsVolume - _player.volume).abs() > 0.01) {
      setState(() => _player.volume = settingsVolume);
      unawaited(
        _playerService.setVolume(settingsVolume).catchError((Object e) {
          _log(
            'settings_volume_apply_failed',
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }),
      );
    }

    if (delta.audioFilters) {
      unawaited(_applyMergedAudioFilters());
    }

    if (delta.multiAudioMix) {
      unawaited(() async {
        final applied = await _applyMultiAudioMix(announce: true);
        if (_currentFile != null && applied) {
          await _reloadCurrentForMixChange();
        }
      }());
    }

    if (delta.mediaSessionEnabled != null) {
      unawaited(_mediaSession.setEnabled(delta.mediaSessionEnabled!));
    }

    if (delta.playlistShuffle != null) {
      _setShuffle(delta.playlistShuffle!);
    }

    if (delta.hwDec != null) {
      _applyHwDec(delta.hwDec!);
    }

    if (delta.seekPreviewEnabled != null) {
      unawaited(_seekPreviewService.setEnabled(delta.seekPreviewEnabled!));
      final source = _player.currentSource;
      if (delta.seekPreviewEnabled! &&
          source != null &&
          source.isFile &&
          !_player.isAudioFile) {
        unawaited(_seekPreviewService.setSource(source.value));
      } else if (!delta.seekPreviewEnabled!) {
        unawaited(_seekPreviewService.setSource(null));
      }
    }

    if (delta.alwaysOnTop != null) {
      unawaited(
        windowManager.setAlwaysOnTop(delta.alwaysOnTop!).catchError((Object e) {
          _log(
            'always_on_top_apply_failed',
            category: DebugLogCategory.system,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }),
      );
    }

    if (delta.rebuildUi && mounted) {
      setState(() {});
    }
  }

  void _initializePlatformFileOpenBridge() {
    final initialFile = _resolveInitialFile(widget.initialFile);
    unawaited(
      _openFileBridge.bootstrap(
        subscriptions: _subscriptions,
        initial: [
          if (initialFile != null && initialFile.isNotEmpty)
            OpenFileRequest(path: initialFile),
        ],
      ),
    );
  }

  /// Resolves a relative CLI path against this process's working directory,
  /// which is only valid for the process's own argv. URLs and URIs pass through.
  static String? _resolveInitialFile(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return trimmed;
    if (PlayableSource.isSupportedUrl(trimmed)) return trimmed;
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(trimmed)) return trimmed;
    return p.normalize(p.absolute(trimmed));
  }

  /// macOS application menu → Flutter (Preferences, updates, File menu).
  void _initializeMacAppMenuBridge() {
    if (!Platform.isMacOS) return;
    const channel = MethodChannel(InstanceModeService.windowMethodChannelName);
    channel.setMethodCallHandler((call) async {
      if (!mounted || _isDisposed) return null;
      switch (call.method) {
        case InstanceModeService.checkForUpdatesMethod:
          await runManualUpdateCheck(
            context: context,
            updateService: _updateService,
            settings: _settings,
            debugLog: widget.debugLog,
            onLog: (event, {message, severity}) {
              _log(
                event,
                category: DebugLogCategory.update,
                message: message,
                severity: severity ?? DebugSeverity.info,
              );
            },
          );
          return null;
        case InstanceModeService.openPreferencesMethod:
          _openSettings();
          return null;
        case InstanceModeService.openFileMethod:
          unawaited(_openFile());
          return null;
        case InstanceModeService.openFolderMethod:
          unawaited(_openFolder());
          return null;
        case InstanceModeService.openPlaylistMethod:
          unawaited(_openPlaylistPicker());
          return null;
        case InstanceModeService.openUrlMethod:
          unawaited(_openUrl());
          return null;
        case InstanceModeService.reopenLastMethod:
          unawaited(_reopenLastFile());
          return null;
        case InstanceModeService.savePlaylistMethod:
          unawaited(_exportPlaylistQueue());
          return null;
        case InstanceModeService.newWindowMethod:
          unawaited(InstanceModeService.openNewWindow());
          return null;
        case InstanceModeService.clearRecentFilesMethod:
          _settings.clearRecentFiles();
          if (Platform.isWindows) {
            unawaited(WindowsShellService.updateJumpList(const []));
          }
          return null;
        case InstanceModeService.openRecentMethod:
          final path = call.arguments;
          if (path is String && path.trim().isNotEmpty) {
            _loadRecentFile(path.trim());
          }
          return null;
        case InstanceModeService.getRecentFilesMethod:
          await _settings.pruneRecentFiles(notifyListeners: false);
          return _settings.recentFiles;
        default:
          return null;
      }
    });
  }

  Future<void> _openRequestedFile(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.forwarded,
  }) async {
    await _openRequestedFileRequest(
      OpenFileRequest(path: filePath),
      forcePlay: forcePlay,
      origin: origin,
    );
  }

  Future<void> _openRequestedFileRequest(
    OpenFileRequest request, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.forwarded,
  }) async {
    final bookmark = request.bookmark;
    if (bookmark != null && BookmarkService.isSupported) {
      _settings.setFileBookmark(request.path, bookmark);
    }
    final filePath = request.path;
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return;
    if (_currentFile == trimmed) {
      _log(
        'open_requested_same_file',
        detailsBuilder: () => {
          'path': trimmed,
          'force_play': forcePlay,
          'is_playing': _player.isPlaying,
        },
      );
      if (SourceOpenPolicy.shouldResumeSameFile(
        forcePlay: forcePlay,
        isPlaying: _player.isPlaying,
      )) {
        unawaited(_playerService.playPause().catchError((_) {}));
        return;
      }
      if (SourceOpenPolicy.shouldRestartSameFile(
        forcePlay: forcePlay,
        isPlaying: _player.isPlaying,
      )) {
        await _loadFile(trimmed, forcePlay: true, origin: origin);
        return;
      }
      return;
    }
    _log(
      'open_requested',
      detailsBuilder: () => {'path': trimmed, 'force_play': forcePlay},
    );
    await _loadFile(trimmed, forcePlay: forcePlay, origin: origin);
  }

  Future<void> _openRequestedFileBatch(List<OpenFileRequest> requests) async {
    if (BookmarkService.isSupported) {
      for (final request in requests) {
        final bookmark = request.bookmark;
        if (bookmark != null) _settings.setFileBookmark(request.path, bookmark);
      }
    }
    _applyDroppedPaths(
      requests.map((request) => request.path),
      origin: SourceOrigin.forwarded,
    );
  }

  void _applySpeed(double speed) {
    unawaited(
      _playerService.setRate(speed).catchError((Object e) {
        _log(
          'playback_rate_apply_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _log(
      'playback_rate_applied',
      detailsBuilder: () => {'rate': speed.toStringAsFixed(2)},
    );
  }

  void _setPlaybackSpeed(double speed, {required String source}) {
    _settings.speed = speed;
    _applySpeed(speed);
    unawaited(_mediaSession.updateRate(speed));
    if (mounted) {
      _showOsdMessage(PlaybackSpeedPolicy.formatLabel(speed));
      setState(() {});
    }
    _log(
      'playback_speed_changed',
      category: DebugLogCategory.ui,
      detailsBuilder: () => {
        'value': speed.toStringAsFixed(2),
        'source': source,
      },
    );
  }

  void _cyclePlaybackSpeed() {
    _setPlaybackSpeed(
      PlaybackSpeedPolicy.cycleNext(_settings.speed),
      source: 'cycle',
    );
  }

  void _nudgePlaybackSpeed({required bool faster}) {
    final next = faster
        ? PlaybackSpeedPolicy.stepFaster(_settings.speed)
        : PlaybackSpeedPolicy.stepSlower(_settings.speed);
    if (next == _settings.speed) return;
    _setPlaybackSpeed(next, source: faster ? 'faster' : 'slower');
  }

  bool _shouldEnableHardwareAcceleration(String hwDec) {
    return HardwareAccelerationService.shouldEnableHardwareAcceleration(hwDec);
  }

  void _applyHwDec(String value) {
    unawaited(
      _playerService
          .setProperty('hwdec', value)
          .then((applied) {
            if (applied) {
              _log(
                'hwdec_property_applied',
                category: DebugLogCategory.hwaccel,
                detailsBuilder: () => {'hwdec': value},
              );
            } else {
              _log(
                'hwdec_property_unavailable',
                category: DebugLogCategory.hwaccel,
                detailsBuilder: () => {'hwdec': value},
                severity: DebugSeverity.warn,
              );
            }
          })
          .catchError((Object e) {
            _log(
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
  void _setShuffle(bool on) {
    if (_settings.playlistShuffle != on) {
      _settings.playlistShuffle = on;
    }
    _playlist.setShuffle(on);
    unawaited(_mediaSession.updateShuffle(on));
  }

  void _applyLoopMode(LoopMode mode) {
    final plMode = switch (mode) {
      LoopMode.none => PlaylistMode.none,
      LoopMode.single => PlaylistMode.single,
      // Queue looping is handled in _advancePlaylist via wrapped indexing.
      LoopMode.loop => PlaylistMode.none,
    };
    unawaited(
      _playerService.setPlaylistMode(plMode).catchError((Object e) {
        _log(
          'loop_mode_apply_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _log('loop_mode_applied', detailsBuilder: () => {'loop_mode': mode.name});
  }

  Future<void> _showPendingUpdateNotice() async {
    final marker = UpdatePendingMarker.readAndClear();
    if (!mounted) return;
    final actualVersion = await UpdateService.currentVersionFromPlatform();
    final decision = UpdateLaunchPolicy.decide(
      marker: marker,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
      actualVersion: actualVersion,
    );
    if (!mounted || !decision.shouldShow) return;
    final targetVersion = decision.targetVersion!;
    final messenger = ScaffoldMessenger.of(context);
    if (decision.kind == UpdateLaunchNoticeKind.success) {
      _log(
        'launch_update_succeeded_notice',
        category: DebugLogCategory.update,
        detailsBuilder: () => {'version': targetVersion},
      );
      messenger.showAppSnackBar(
        AppLocalizations.of(context).snackUpdatedToVersion(targetVersion),
      );
    } else {
      _log(
        'launch_update_failed_notice',
        category: DebugLogCategory.update,
        severity: DebugSeverity.warn,
        detailsBuilder: () => {
          'target': targetVersion,
          'actual': actualVersion,
        },
      );
      messenger.showAppSnackBar(
        AppLocalizations.of(context).snackUpdateMayHaveFailed(targetVersion),
      );
    }
  }

  // ── Update check with cooldown ────────────────────────────

  Future<void> _checkForUpdates() async {
    if (!_settings.shouldCheckForUpdate) return;
    _log(
      'launch_update_check_started',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'last_check_epoch': _settings.lastUpdateCheck},
    );
    final update = await _updateService.checkForUpdate(
      channel: _settings.updateChannel,
    );
    final checkSucceeded = _updateService.lastCheckSucceeded;
    if (checkSucceeded) {
      _settings.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
    }
    if (update != null && mounted) {
      _log(
        'launch_update_available',
        category: DebugLogCategory.update,
        detailsBuilder: () => {'version': update.version},
      );
      _showUpdateSnackbar(update);
    } else {
      if (checkSucceeded) {
        _log('launch_update_not_available', category: DebugLogCategory.update);
      } else {
        _log(
          'launch_update_check_failed',
          category: DebugLogCategory.update,
          severity: DebugSeverity.warn,
        );
      }
    }
  }

  void _showUpdateSnackbar(UpdateInfo update) {
    if (!mounted) return;
    _log(
      'update_snackbar_shown',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'version': update.version},
    );
    showAppSnackBar(
      context,
      AppLocalizations.of(context).snackUpdateAvailable(update.version),
      duration: _updateSnackbarDuration,
      action: SnackBarAction(
        label: updateActionLabel(AppLocalizations.of(context)),
        onPressed: () => triggerUpdateAction(
          context: context,
          info: update,
          updateService: _updateService,
          channelName: _settings.updateChannel.name,
          debugLog: widget.debugLog,
        ),
      ),
    );
  }

  // ── File handling ─────────────────────────────────────────

  Future<void> _openFile() async {
    _log('file_picker_open_requested');
    try {
      final file = await _pickers.pickMediaFile();

      if (file == null) {
        _log('file_picker_cancelled');
        return;
      }
      final path = FilePickerPath.fromPlatformFilePath(file.path);
      if (path == null) {
        _log('file_picker_invalid_path', severity: DebugSeverity.warn);
        if (mounted) {
          showAppSnackBar(
            context,
            AppLocalizations.of(context).snackCouldNotReadSelectedFile,
          );
        }
        return;
      }

      await _captureBookmarkFor(path);
      await _openPathOrPlaylist(path, origin: SourceOrigin.fileDialog);
    } on PlatformException catch (e) {
      _log(
        'file_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFilePickerFailed(detail),
        );
      }
    } catch (e) {
      _log(
        'file_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackUnableToOpenFilePicker,
        );
      }
    }
  }

  Future<void> _openFolder({bool playNow = true}) async {
    _log('folder_picker_open_requested');
    try {
      final folder = await _pickers.pickFolder();
      if (folder == null || folder.trim().isEmpty) {
        _log('folder_picker_cancelled');
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _settings.lastOpenDirectory = folder.trim();
      await _captureBookmarkFor(folder.trim());
      final scan = await MediaFolderScanner.scan(
        folder,
        maxItems: PlaylistService.maxQueueItems,
      );
      if (!mounted) return;
      if (scan.paths.isEmpty) {
        if (mounted) {
          showAppSnackBar(context, l10n.snackNoSupportedMediaInFolder);
        }
        return;
      }
      _enqueue(scan.paths, playNow: playNow, origin: SourceOrigin.folderDialog);
      if (mounted && (scan.skipped > 0 || scan.truncated > 0)) {
        final parts = <String>[];
        if (scan.skipped > 0) {
          parts.add(l10n.snackFolderScanSkipped(scan.skipped));
        }
        if (scan.truncated > 0) {
          parts.add(
            l10n.snackQueueTruncated(
              PlaylistService.maxQueueItems,
              scan.truncated,
            ),
          );
        }
        showAppSnackBar(context, parts.join(' '));
      }
    } on PlatformException catch (e) {
      final detail = (e.message == null || e.message!.trim().isEmpty)
          ? e.code
          : e.message!.trim();
      _log(
        'folder_picker_platform_exception',
        message: detail,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFolderScanFailed(detail),
        );
      }
    } catch (e) {
      _log(
        'folder_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFolderScanFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _openUrl() async {
    final l10n = AppLocalizations.of(context);
    final url = await _pickers.promptForUrl(context);
    if (!mounted) return;
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (!PlayableSource.isSupportedUrl(trimmed)) {
      if (mounted) {
        showAppSnackBar(context, l10n.snackInvalidStreamUrl);
      }
      return;
    }
    await _loadSource(PlayableSource.url(trimmed));
  }

  Future<void> _loadFile(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    return _openPathOrPlaylist(filePath, forcePlay: forcePlay, origin: origin);
  }

  Future<void> _openPathOrPlaylist(
    String filePath, {
    bool forcePlay = false,
    SourceOrigin origin = SourceOrigin.other,
  }) async {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return;
    if (PlayableSource.isSupportedUrl(trimmed)) {
      await _loadSource(PlayableSource.url(trimmed), forcePlay: forcePlay);
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
      await _importPlaylistFile(trimmed, playNow: true, origin: origin);
      return;
    }
    await _loadSource(
      PlayableSource.file(trimmed),
      forcePlay: forcePlay,
      origin: origin,
    );
  }

  Future<void> _openPlaylistPicker({bool playNow = true}) async {
    _log('playlist_picker_open_requested');
    try {
      final path = await _pickers.pickPlaylistFile();
      if (path == null) return;
      await _captureBookmarkFor(path);
      final parent = p.dirname(path);
      if (parent.isNotEmpty && parent != path) {
        await _captureBookmarkFor(parent);
      }
      await _importPlaylistFile(
        path,
        playNow: playNow,
        origin: SourceOrigin.fileDialog,
      );
    } on PlatformException catch (e) {
      _log(
        'playlist_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFilePickerFailed(detail),
        );
      }
    } catch (e) {
      _log(
        'playlist_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackUnableToOpenFilePicker,
        );
      }
    }
  }

  Future<void> _exportPlaylistQueue() async {
    if (_playlist.isEmpty) return;
    _log('playlist_export_requested', category: DebugLogCategory.ui);
    final l10n = AppLocalizations.of(context);
    try {
      final content = M3uPlaylist.encode(_playlist.items);
      final path = await _pickers.pickPlaylistSavePath(
        dialogTitle: l10n.buttonSavePlaylist,
        content: content,
      );
      if (path == null) return;
      _pickers.rememberLastOpenDirectory(path);
      if (!mounted) return;
      showAppSnackBar(context, l10n.snackPlaylistExportSaved);
      _log(
        'playlist_exported',
        detailsBuilder: () => {
          'path': path,
          'count': '${_playlist.items.length}',
        },
      );
    } on PlatformException catch (e) {
      _log(
        'playlist_export_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(context, l10n.snackPlaylistExportFailed);
      }
    } catch (e) {
      _log(
        'playlist_export_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(context, l10n.snackPlaylistExportFailed);
      }
    }
  }

  Future<void> _importPlaylistFile(
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
        if (mounted) {
          showAppSnackBar(
            context,
            AppLocalizations.of(context).snackPlaylistEmptyOrInvalid,
          );
        }
        return;
      }
      _pickers.rememberLastOpenDirectory(playlistPath);
      _rememberRecentAndJumpList(playlistPath);
      _enqueueSources(sources, playNow: playNow);
      _log(
        'playlist_imported',
        detailsBuilder: () => {
          'path': playlistPath,
          'count': sources.length,
          'play_now': playNow,
        },
      );
    } catch (e) {
      _log(
        'playlist_import_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackPlaylistImportFailed,
        );
      }
    }
  }

  Future<void> _loadSource(
    PlayableSource source, {
    bool forcePlay = false,
    bool syncPlaylist = true,
    bool applyResume = true,
    bool? playOverride,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    return _playback.loadQueue.enqueue(
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
        _log(
          'load_queue_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      },
    );
  }

  Future<void> _refreshMediaMetadata(
    PlayableSource source, {
    Duration? duration,
    bool exportArt = true,
    int? gen,
  }) async {
    if (_isDisposed) return;
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final pushToSession = _settings.mediaSessionEnabled;
    String? artist;
    String? album;
    String? metaTitle;
    try {
      artist = await _playerService.getProperty('metadata/by-key/artist');
      if (pushToSession) {
        album = await _playerService.getProperty('metadata/by-key/album');
      }
      metaTitle = await _playerService.getProperty('metadata/by-key/title');
    } catch (_) {
      // Metadata is best-effort; title falls back to display name.
    }
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final title = (metaTitle != null && metaTitle.trim().isNotEmpty)
        ? metaTitle.trim()
        : source.displayName;
    final artistName = (artist != null && artist.trim().isNotEmpty)
        ? artist.trim()
        : null;
    if (mounted) {
      setState(() {
        _mediaDisplayTitle = title;
        _mediaDisplayArtist = artistName;
      });
    }
    if (!pushToSession || !_settings.mediaSessionEnabled) return;
    String? artUri;
    if (exportArt && _player.hasAlbumArtTrack) {
      artUri = await _exportAlbumArtForMediaSession();
    } else if (!exportArt) {
      artUri = _lastMediaSessionArtUri;
    }
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    await _mediaSession.updateMetadata(
      title: title,
      artist: artistName,
      album: (album != null && album.trim().isNotEmpty) ? album.trim() : null,
      duration: duration ?? _player.duration,
      artUri: artUri,
      trackIdentity: '${source.value}#${_playback.loadGeneration}',
    );
  }

  Future<String?> _exportAlbumArtForMediaSession() async {
    final exportGen = ++_mediaSessionArtExportGen;
    try {
      final bytes = await _playerService.screenshot(format: 'image/jpeg');
      if (exportGen != _mediaSessionArtExportGen) return null;
      if (bytes == null || bytes.isEmpty) return null;
      final dir = _mediaSessionArtDirectory();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      if (exportGen != _mediaSessionArtExportGen) return null;
      // Prefix with the pid so instances never share or delete each other's art.
      final prefix = 'artwork-$pid-';
      final file = File(p.join(dir.path, '$prefix$exportGen.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      if (exportGen != _mediaSessionArtExportGen) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup for an obsolete artwork export.
        }
        return null;
      }
      final uri = file.uri.toString();
      _lastMediaSessionArtUri = uri;
      // Own older exports go now; other instances' files only once stale, so
      // art left by a crashed instance does not pile up.
      final staleBefore = DateTime.now().subtract(const Duration(days: 1));
      for (final older in dir.listSync().whereType<File>().where((candidate) {
        if (candidate.path == file.path) return false;
        final name = p.basename(candidate.path);
        if (!name.startsWith('artwork-') || !name.endsWith('.jpg')) {
          return false;
        }
        if (name.startsWith(prefix)) return true;
        try {
          return candidate.lastModifiedSync().isBefore(staleBefore);
        } catch (_) {
          return false;
        }
      })) {
        try {
          await older.delete();
        } catch (_) {
          // Artwork cleanup is best-effort.
        }
      }
      return uri;
    } catch (e) {
      _log(
        'media_session_art_export_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      return null;
    }
  }

  void _maybeUpdateMediaSessionPosition(Duration pos) {
    if (!_playback.mediaSessionThrottle.shouldSend(DateTime.now())) {
      return;
    }
    unawaited(_mediaSession.updatePosition(pos, playing: _player.isPlaying));
  }

  DateTime? _lastTaskbarProgressAt;

  void _maybeUpdateTaskbarProgress(Duration pos) {
    if (!Platform.isWindows || !_player.isPlaying) return;
    final dur = _player.duration;
    if (dur.inMilliseconds <= 0) return;
    final now = DateTime.now();
    final last = _lastTaskbarProgressAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastTaskbarProgressAt = now;
    final progress = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    unawaited(WindowsShellService.setTaskbarProgress(progress));
  }

  Future<void> _syncWindowsJumpList() async {
    if (!Platform.isWindows) return;
    await WindowsShellService.updateJumpList(_settings.recentFiles);
  }

  void _rememberRecentAndJumpList(String path) {
    _settings.addRecentFile(path);
    unawaited(_syncWindowsJumpList());
  }

  Future<void> _refreshChaptersIfNeeded({int? gen}) async {
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final countRaw = await _playerService.getProperty('chapter-list/count');
    final count = int.tryParse(countRaw ?? '') ?? 0;
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    if (!_playback.chapterGate.shouldRefresh(
      path: _currentFile,
      chapterCount: count,
    )) {
      return;
    }
    await _refreshChapters(expectedCount: count, gen: gen);
    if (!mounted || _isDisposed) return;
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    _playback.chapterGate.markFetched(path: _currentFile, chapterCount: count);
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
    if (_isDisposed) return false;
    final requestedValue = source.value.trim();
    final normalizedSource = source.isUrl
        ? PlayableSource.url(requestedValue)
        : PlayableSource.file(await _resolveSandboxedPath(requestedValue));
    final normalizedValue = normalizedSource.value;

    final fileExists =
        _headlessMedia ||
        !normalizedSource.isFile ||
        await PathProbe.fileExists(normalizedValue);
    if (_isDisposed) return false;
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

    final priorQueue = syncPlaylist ? _playlist.capture() : null;
    if (syncPlaylist) {
      _playlist.setPlayingSource(normalizedSource);
    }
    final queueRevision = _playlist.revision;
    void restoreQueue() {
      if (priorQueue == null) return;
      if (_playlist.revision != queueRevision) return;
      _playlist.restore(priorQueue);
    }

    final ext = normalizedSource.extension ?? '';
    _log(
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
      _log(
        'file_load_unrecognized_extension',
        detailsBuilder: () => {'extension': ext, 'path': normalizedValue},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackUnsupportedFileType,
        );
      }
    }
    final gen = _playback.beginLoad();
    _mediaSessionArtExportGen++;
    _lastMediaSessionArtUri = null;
    if (SourceLoadPreOpenPolicy.shouldAbortBeforeOpen(
      mounted: mounted,
      isDisposed: _isDisposed,
    )) {
      restoreQueue();
      return false;
    }
    _persistResumePosition();
    _playback.chapterGate.invalidate();
    setState(() {
      _player.beginSourceLoad(normalizedSource, ext);
      _mediaDisplayTitle = null;
      _mediaDisplayArtist = null;
    });
    await _advancedPlayback.setSource(normalizedSource);
    _log(
      'media_type_initial_state',
      detailsBuilder: () => {
        'is_audio_file': _player.isAudioFile,
        'has_video_output': false,
      },
    );

    try {
      _player.fileOpenInProgress = true;
      _mixLoadState.reset();
      await _playerService.setProperty('lavfi-complex', '');
      _player.mixActive = false;
      final open = SourceOpenPolicy.paramsFor(
        normalizedPath: normalizedValue,
        forcePlay: forcePlay,
        autoPlaySetting: _settings.autoPlay,
        playOverride: playOverride,
      );
      await _playerService.open(
        open.path,
        play: open.play,
        allowUnc: origin.allowsUnc,
      );
      // Re-apply after open because libmpv may reset per-file properties.
      await _advancedPlayback.applyForCurrentSource();
    } catch (e) {
      final failureKind = SourceLoadFailurePolicy.classify(e);
      final failureReaction = SourceLoadOpenPolicy.openFailureReaction(
        kind: failureKind,
        isLoadCurrent: _playback.isLoadCurrent(gen),
        mounted: mounted,
      );
      _log(
        SourceLoadFailurePolicy.logEvent(failureKind),
        message: e.toString(),
        detailsBuilder: () => {'source': normalizedValue},
        severity: failureReaction.logAsWarning
            ? DebugSeverity.warn
            : DebugSeverity.error,
      );
      restoreQueue();
      if (!failureReaction.shouldUpdateUi) return false;
      await _advancedPlayback.setSource(null);
      if (!mounted) return false;
      setState(_player.clearSourceOnLoadFailure);
      unawaited(_seekPreviewService.setSource(null));
      final failureMessage = _loadUserMessageText(
        SourceLoadFailurePolicy.userMessage(failureKind),
      );
      if (failureBatch != null) {
        failureBatch.add(failureMessage);
      } else {
        showAppSnackBar(context, failureMessage);
      }
      return false;
    } finally {
      _player.fileOpenInProgress = false;
    }

    if (_stopInProgress) return true;

    final postOpen = SourceLoadPostOpenPolicy.plan(
      isLoadCurrent: _playback.isLoadCurrent(gen),
      isDisposed: _isDisposed,
      mounted: mounted,
      normalizedSource: normalizedSource,
      isAudioFile: _player.isAudioFile,
    );
    final followUp = SourceLoadPostOpenPolicy.followUpFor(postOpen);
    if (!postOpen.shouldProceed) {
      return true;
    }
    if (followUp.shouldCacheTracks) {
      _cacheTracksForCurrentLoad(_playerService.currentTracks, gen: gen);
    }

    if (followUp.shouldClearSeekPreview) {
      unawaited(_seekPreviewService.setSource(null));
    } else if (followUp.seekPreviewPath != null) {
      unawaited(_seekPreviewService.setSource(followUp.seekPreviewPath));
    }

    _log(
      'file_load_succeeded',
      detailsBuilder: () => {
        'source': normalizedValue,
        'source_type': normalizedSource.type.name,
        'auto_play': _settings.autoPlay,
      },
    );

    try {
      if (followUp.shouldPersistRecent) {
        _rememberRecentAndJumpList(normalizedValue);
      }
      if (followUp.shouldRememberOpenDirectory) {
        _pickers.rememberLastOpenDirectory(normalizedValue);
      }
      _log(
        followUp.recentPersistLogEvent,
        category: DebugLogCategory.settings,
        detailsBuilder: () => {'source': normalizedValue},
      );
    } catch (e) {
      _log(
        'recent_file_persist_failed',
        category: DebugLogCategory.settings,
        message: e.toString(),
        detailsBuilder: () => {'source': normalizedValue},
        severity: DebugSeverity.warn,
      );
    }

    if (followUp.shouldRefreshUi) {
      setState(() {});
    }

    _player.resumePathInProgress = followUp.resumeTrackingPath;
    if (followUp.shouldApplyAudioFilters) {
      await _applyMergedAudioFilters(gen: gen);
    }
    if (followUp.shouldRefreshChapters) {
      await _refreshChapters(gen: gen);
    }
    if (followUp.shouldApplyMultiAudioMix) {
      await _applyMultiAudioMix(gen: gen);
    }
    if (followUp.shouldApplyResume && applyResume) {
      await _maybeApplyResume(normalizedValue, gen: gen);
    }
    if (followUp.shouldUpdateMediaSessionMetadata) {
      unawaited(_refreshMediaMetadata(normalizedSource, gen: gen));
    }
    return true;
  }

  void _cacheTracksForCurrentLoad(
    Tracks tracks, {
    bool refreshChapters = false,
    int? gen,
  }) {
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final result = _player.cacheTracksForLoad(
      tracks,
      mixLoadState: _mixLoadState,
      multiAudioMixEnabled: _settings.multiAudioMix,
      refreshChapters: refreshChapters,
    );
    if (result.audioOnlyChanged) {
      setState(() {});
      _syncIdleInhibit();
      unawaited(_applyMergedAudioFilters(gen: gen));
    }
    if (result.refreshChapters) {
      unawaited(_refreshChaptersIfNeeded(gen: gen));
    }
    if (result.shouldRefreshMix) {
      unawaited(_applyMultiAudioMix(gen: gen));
    }
  }

  void _onDragDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    _applyDroppedPaths(
      details.files.map((file) => file.path),
      origin: SourceOrigin.dragDrop,
    );
  }

  void _applyDroppedPaths(
    Iterable<String> rawPaths, {
    required SourceOrigin origin,
  }) {
    final batch = DropPathBatchPolicy.fromRawPaths(
      rawPaths: rawPaths,
      windows: Platform.isWindows,
      allowUnc: origin.allowsUnc,
    );
    if (batch.isEmpty) {
      _log(
        'drop_file_invalid_path',
        detailsBuilder: () => {'count': rawPaths.length},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showAppSnackBar(context, l10n.snackCouldNotReadDroppedFile);
      }
      return;
    }
    _log(
      'drop_file_received',
      detailsBuilder: () => {
        'path': batch.paths.first,
        'count': batch.paths.length,
        'skipped': batch.skippedCount,
      },
    );
    if (batch.skippedCount > 0 && mounted) {
      final l10n = AppLocalizations.of(context);
      showAppSnackBar(
        context,
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
      await _captureBookmarkFor(path);
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
          _log(
            'drop_playlist_parse_failed',
            message: e.toString(),
            detailsBuilder: () => {'path': path},
            severity: DebugSeverity.warn,
          );
        }
        continue;
      }
      if (!_headlessMedia) {
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
    if (inaccessible > 0 && mounted) {
      showAppSnackBar(
        context,
        AppLocalizations.of(context).snackDropPathInaccessible,
      );
    }
    if (media.isEmpty) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackPlaylistEmptyOrInvalid,
        );
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
          unawaited(_loadSource(only, origin: origin));
        }
      case DropFileAction.enqueuePlayNow:
        _enqueueSources(media, playNow: true, origin: origin);
    }
  }

  void _onDragEntered() {
    if (_isDragging) return;
    _log('drag_entered', category: DebugLogCategory.ui);
    setState(() => _isDragging = true);
  }

  void _onDragExited() {
    if (!_isDragging) return;
    _log('drag_exited', category: DebugLogCategory.ui);
    setState(() => _isDragging = false);
  }

  void _loadRecentFile(String path) {
    unawaited(_settings.pruneRecentFiles());
    _log('recent_file_open_requested', detailsBuilder: () => {'path': path});
    final source = PlayableSource.fromStored(path);
    if (source == null) return;
    if (source.isUrl) {
      unawaited(_loadSource(source, origin: SourceOrigin.recents));
    } else {
      unawaited(_openRequestedFile(source.value, origin: SourceOrigin.recents));
    }
  }

  Future<void> _reopenLastFile() async {
    await _settings.pruneRecentFiles();
    if (!mounted || _isDisposed) return;
    final recents = _settings.recentFiles;
    if (recents.isEmpty) {
      _log('reopen_last_fallback_open_picker', category: DebugLogCategory.ui);
      await _openFile();
      return;
    }
    final lastPath = recents.first;
    _log(
      'reopen_last_requested',
      category: DebugLogCategory.ui,
      detailsBuilder: () => {'path': lastPath},
    );
    final source = PlayableSource.fromStored(lastPath);
    if (source == null) return;
    if (source.isUrl) {
      await _loadSource(source, origin: SourceOrigin.recents);
    } else {
      await _openRequestedFile(source.value, origin: SourceOrigin.recents);
    }
  }

  // ── Navigation ────────────────────────────────────────────

  void _openSettings() {
    if (!mounted) return;
    _log('open_settings_requested', category: DebugLogCategory.ui);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: _settingsFwdTransition,
        reverseTransitionDuration: _settingsRevTransition,
        pageBuilder: (_, _, _) => SettingsScreen(
          settings: _settings,
          debugLog: widget.debugLog,
          updateService: _updateService,
          onEditKeybinds: () => unawaited(
            showKeybindsDialog(context: context, settings: _settings),
          ),
        ),
        opaque: false,
        transitionsBuilder: (context, animation, _, child) {
          // Mask ramps up quickly to hide the player underneath the
          // semi-transparent settings scaffold when blur is active.
          final visuals = context.windowVisuals;
          final maskOpacity = Curves.easeOut.transform(
            (animation.value / 0.45).clamp(0.0, 1.0),
          );
          final zoom = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
              reverseCurve: const Interval(0.0, 0.5, curve: Curves.easeIn),
            ),
          );
          final scale = Tween<double>(begin: 0.94, end: 1.0).animate(zoom);
          final settleOffset = Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(zoom);

          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: visuals.overlayTopColor.withValues(alpha: maskOpacity),
              ),
              FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: settleOffset,
                  child: ScaleTransition(scale: scale, child: child),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Keyboard shortcuts ────────────────────────────────────

  bool _playerRouteIsCurrent() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  bool _shortcutFocusInPath() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    return primary == _shortcutFocus ||
        primary.ancestors.contains(_shortcutFocus);
  }

  bool _isEditableFocus(FocusNode primary) {
    final ctx = primary.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onGlobalShortcutKey(KeyEvent event) {
    if (!mounted || _isDisposed) return false;
    if (!_playerRouteIsCurrent()) return false;
    if (_shortcutFocusInPath()) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _isEditableFocus(primary)) return false;
    return _handleKeyEvent(_shortcutFocus, event) == KeyEventResult.handled;
  }

  void _restoreShortcutFocus({bool refocusNativeWindow = true}) {
    if (!mounted || _isDisposed) return;
    if (_shortcutFocus.canRequestFocus) {
      _shortcutFocus.requestFocus();
    }
    if (refocusNativeWindow) {
      unawaited(windowManager.focus().catchError((_) {}));
    }
  }

  @override
  void onWindowFocus() {
    _restoreShortcutFocus(refocusNativeWindow: false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final hk = HardwareKeyboard.instance;
    final pressed = LogicalKeyboardKey.expandSynonyms(hk.logicalKeysPressed);
    final controlPressed =
        hk.isControlPressed || pressed.contains(LogicalKeyboardKey.control);
    final metaPressed =
        hk.isMetaPressed || pressed.contains(LogicalKeyboardKey.meta);
    final shiftPressed =
        hk.isShiftPressed || pressed.contains(LogicalKeyboardKey.shift);
    final altPressed =
        hk.isAltPressed || pressed.contains(LogicalKeyboardKey.alt);
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        !metaPressed &&
        !controlPressed &&
        !shiftPressed &&
        !altPressed) {
      return _handleEscapeBack();
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.f1 ||
            (event.logicalKey == LogicalKeyboardKey.question) ||
            (event.logicalKey == LogicalKeyboardKey.slash && shiftPressed))) {
      unawaited(showKeybindsDialog(context: context, settings: _settings));
      return KeyEventResult.handled;
    }
    final custom = _settings.keybinds;
    var shortcut = PlayerShortcutsService.resolve(
      event: event,
      hasMedia: _currentFile != null,
      isMetaPressed: metaPressed,
      isControlPressed: controlPressed,
      isShiftPressed: shiftPressed,
      isAltPressed: altPressed,
      customBindings: custom.isEmpty ? null : custom,
    );
    if (shortcut == null && _settings.advancedPlaybackToolsEnabled) {
      shortcut = PlayerShortcutsService.resolveAdvanced(
        event: event,
        isMetaPressed: metaPressed,
        isControlPressed: controlPressed,
        isShiftPressed: shiftPressed,
        customBindings: custom.isEmpty ? null : custom,
      );
    }

    final drawerOpen = _scaffoldKey.currentState?.isEndDrawerOpen ?? false;
    if (drawerOpen) {
      switch (shortcut) {
        case PlayerShortcutAction.seekForward:
        case PlayerShortcutAction.seekBack:
        case PlayerShortcutAction.volumeUp:
        case PlayerShortcutAction.volumeDown:
          return KeyEventResult.ignored;
        default:
          break;
      }
    }

    switch (shortcut) {
      case PlayerShortcutAction.openFile:
        _log('shortcut_open_file', category: DebugLogCategory.ui);
        _openFile();
        return KeyEventResult.handled;
      case PlayerShortcutAction.openUrl:
        _log('shortcut_open_url', category: DebugLogCategory.ui);
        unawaited(_openUrl());
        return KeyEventResult.handled;
      case PlayerShortcutAction.reopenLast:
        _log('shortcut_reopen_last', category: DebugLogCategory.ui);
        unawaited(_reopenLastFile());
        return KeyEventResult.handled;
      case PlayerShortcutAction.playPause:
        _revealFullscreenChrome();
        unawaited(
          _playerService.playPause().catchError((Object e) {
            _log(
              'shortcut_play_pause_failed',
              category: DebugLogCategory.ui,
              message: e.toString(),
              severity: DebugSeverity.warn,
            );
          }),
        );
        _log('shortcut_play_pause', category: DebugLogCategory.ui);
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekForward:
        _log('shortcut_seek_forward', category: DebugLogCategory.ui);
        _revealFullscreenChrome();
        _pulseOsd();
        _seekRelative(_seekStep);
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekBack:
        _log('shortcut_seek_back', category: DebugLogCategory.ui);
        _revealFullscreenChrome();
        _pulseOsd();
        _seekRelative(_seekStepBack);
        return KeyEventResult.handled;
      case PlayerShortcutAction.volumeUp:
        _log('shortcut_volume_up', category: DebugLogCategory.ui);
        _adjustVolume(5);
        return KeyEventResult.handled;
      case PlayerShortcutAction.volumeDown:
        _log('shortcut_volume_down', category: DebugLogCategory.ui);
        _adjustVolume(-5);
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleMute:
        _log('shortcut_toggle_mute', category: DebugLogCategory.ui);
        _toggleMute();
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleFullscreen:
        _log('shortcut_toggle_fullscreen', category: DebugLogCategory.ui);
        _revealFullscreenChrome();
        unawaited(_toggleFullscreen());
        return KeyEventResult.handled;
      case PlayerShortcutAction.exitFullscreen:
        // Bare Escape is handled above; keep this for custom/accelerator paths.
        return _handleEscapeBack();
      case PlayerShortcutAction.chapterNext:
        if (_canStepVideoFrame) {
          _log('shortcut_frame_forward', category: DebugLogCategory.ui);
          unawaited(_stepFrame(forward: true));
          return KeyEventResult.handled;
        }
        _log('shortcut_chapter_next', category: DebugLogCategory.ui);
        unawaited(_stepChapter(1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.chapterPrev:
        if (_canStepVideoFrame) {
          _log('shortcut_frame_back', category: DebugLogCategory.ui);
          unawaited(_stepFrame(forward: false));
          return KeyEventResult.handled;
        }
        _log('shortcut_chapter_prev', category: DebugLogCategory.ui);
        unawaited(_stepChapter(-1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.screenshot:
        _log('shortcut_screenshot', category: DebugLogCategory.ui);
        unawaited(_takeScreenshot());
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleAudioTrack:
        _log('shortcut_cycle_audio', category: DebugLogCategory.ui);
        unawaited(_cycleAudioTrack());
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleSubtitleTrack:
        _log('shortcut_cycle_sub', category: DebugLogCategory.ui);
        unawaited(_cycleSubtitleTrack());
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleSubtitle:
        _log('shortcut_toggle_sub', category: DebugLogCategory.ui);
        unawaited(_toggleSubtitleVisibility());
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleEqualizer:
        _log('shortcut_toggle_eq', category: DebugLogCategory.ui);
        _toggleEqualizer();
        return KeyEventResult.handled;
      case PlayerShortcutAction.playlistNext:
        _log('shortcut_playlist_next', category: DebugLogCategory.ui);
        unawaited(_advancePlaylist(1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.playlistPrev:
        _log('shortcut_playlist_prev', category: DebugLogCategory.ui);
        unawaited(_advancePlaylist(-1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleCompactMode:
        _log('shortcut_toggle_compact', category: DebugLogCategory.ui);
        unawaited(_toggleCompactMode());
        return KeyEventResult.handled;
      case PlayerShortcutAction.newWindow:
        _log('shortcut_new_window', category: DebugLogCategory.ui);
        unawaited(InstanceModeService.openNewWindow());
        return KeyEventResult.handled;
      case PlayerShortcutAction.speedSlower:
        _log('shortcut_speed_slower', category: DebugLogCategory.ui);
        _nudgePlaybackSpeed(faster: false);
        return KeyEventResult.handled;
      case PlayerShortcutAction.speedFaster:
        _log('shortcut_speed_faster', category: DebugLogCategory.ui);
        _nudgePlaybackSpeed(faster: true);
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleSpeed:
        _log('shortcut_cycle_speed', category: DebugLogCategory.ui);
        _cyclePlaybackSpeed();
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleAdvancedLoop:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        unawaited(_advancedPlayback.cycleLoop());
        return KeyEventResult.handled;
      case PlayerShortcutAction.subtitleDelayBack:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        unawaited(_advancedPlayback.adjustSubtitleDelay(-100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.subtitleDelayForward:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        unawaited(_advancedPlayback.adjustSubtitleDelay(100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.audioDelayBack:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        unawaited(_advancedPlayback.adjustAudioDelay(-100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.audioDelayForward:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        unawaited(_advancedPlayback.adjustAudioDelay(100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.addPlaybackMarker:
        if (!_settings.advancedPlaybackToolsEnabled || _currentFile == null) {
          return KeyEventResult.ignored;
        }
        _advancedPlayback.addMarker();
        return KeyEventResult.handled;
      case null:
        return KeyEventResult.ignored;
    }
  }

  double _volumeBeforeMute = 100.0;

  bool get _canStepVideoFrame {
    final source = _player.currentSource;
    if (source == null || _player.isPlaying || _player.isAudioFile) {
      return false;
    }
    final extension = source.extension?.toLowerCase();
    return _player.hasVideoOutput ||
        (extension != null &&
            PlayerPathUtils.videoExtensions.contains(extension));
  }

  Future<void> _stepFrame({required bool forward}) async {
    final stepped = await _playerService.stepFrame(forward: forward);
    if (stepped || _isDisposed) return;
    _log(
      'shortcut_frame_step_failed',
      message: forward ? 'forward' : 'backward',
      severity: DebugSeverity.warn,
    );
  }

  void _seekRelative(Duration offset) {
    final target = PlayerController.clampSeekTarget(
      position: _player.position,
      offset: offset,
      duration: _player.duration,
    );
    if (target == null) return;
    unawaited(
      _playerService.seek(target).catchError((Object e) {
        _log(
          'seek_relative_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _log(
      'seek_relative',
      detailsBuilder: () => {'target_ms': target.inMilliseconds},
    );
  }

  void _adjustVolume(double delta) {
    final newVol = VolumePolicy.adjustVolume(
      current: _player.volume,
      delta: delta,
    );
    unawaited(
      _playerService.setVolume(newVol).catchError((Object e) {
        _log(
          'volume_adjust_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _settings.volume = newVol;
    _revealFullscreenChrome();
    if (mounted) {
      _showOsdMessage(AppLocalizations.of(context).osdVolume(newVol.round()));
    }
    _log(
      'volume_adjusted',
      detailsBuilder: () => {'volume': newVol.toStringAsFixed(2)},
    );
  }

  void _toggleMute() {
    final wasMuted = _player.volume <= 0;
    final toggle = VolumePolicy.toggleMute(
      currentVolume: _player.volume,
      volumeBeforeMute: _volumeBeforeMute,
    );
    _volumeBeforeMute = toggle.volumeBeforeMute;
    unawaited(
      _playerService.setVolume(toggle.newVolume).catchError((Object e) {
        _log(
          'mute_toggle_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    _settings.volume = toggle.newVolume;
    _revealFullscreenChrome();
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _showOsdMessage(
        toggle.newVolume <= 0
            ? l10n.osdMuted
            : l10n.osdVolume(toggle.newVolume.round()),
      );
    }
    _log(
      wasMuted ? 'mute_disabled' : 'mute_enabled',
      detailsBuilder: () => wasMuted
          ? {'restored_volume': toggle.newVolume}
          : {'previous_volume': toggle.volumeBeforeMute},
    );
  }

  bool _fullscreenToggleInFlight = false;
  bool _isFullscreen = false;

  bool get _showPlayerChrome => !_isFullscreen || _fullscreenChromeVisible;

  void _revealFullscreenChrome() {
    if (!_isFullscreen) return;
    if (!_fullscreenChromeVisible && mounted) {
      setState(() => _fullscreenChromeVisible = true);
    }
    _scheduleFullscreenChromeHide();
  }

  void _scheduleFullscreenChromeHide() {
    _fullscreenChromeHideTimer?.cancel();
    if (!_isFullscreen) return;
    _fullscreenChromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isDisposed || !_isFullscreen) return;
      setState(() => _fullscreenChromeVisible = false);
    });
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = true;
      _fullscreenChromeVisible = true;
    });
    _scheduleFullscreenChromeHide();
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullscreenChromeHideTimer?.cancel();
    if (!mounted) {
      _isFullscreen = false;
      _fullscreenChromeVisible = true;
      return;
    }
    setState(() {
      _isFullscreen = false;
      _fullscreenChromeVisible = true;
    });
  }

  /// Escape: close queue drawer → exit fullscreen → otherwise ignore.
  KeyEventResult _handleEscapeBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isEndDrawerOpen ?? false) {
      _log('shortcut_close_queue_drawer', category: DebugLogCategory.ui);
      scaffold!.closeEndDrawer();
      return KeyEventResult.handled;
    }
    if (_isFullscreen) {
      _log('shortcut_exit_fullscreen', category: DebugLogCategory.ui);
      unawaited(_exitFullscreen());
      return KeyEventResult.handled;
    }
    // Cache can drift if fullscreen was entered outside our toggle path;
    // reconcile asynchronously without swallowing Escape when windowed.
    unawaited(_exitFullscreenIfActuallyFullscreen());
    return KeyEventResult.ignored;
  }

  Future<void> _exitFullscreenIfActuallyFullscreen() async {
    try {
      if (!await windowManager.isFullScreen()) return;
      if (!mounted) return;
      setState(() => _isFullscreen = true);
      _log('shortcut_exit_fullscreen', category: DebugLogCategory.ui);
      await _exitFullscreen();
    } catch (e) {
      _log(
        'fullscreen_reconcile_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreenToggleInFlight) return;
    _fullscreenToggleInFlight = true;
    try {
      final enabled = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!enabled);
      // Verify state actually changed (Wayland / tiling WMs may reject).
      final actual = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isFullscreen = actual;
          if (actual) {
            _fullscreenChromeVisible = true;
          } else {
            _fullscreenChromeHideTimer?.cancel();
            _fullscreenChromeVisible = true;
          }
        });
        if (actual) {
          _scheduleFullscreenChromeHide();
        }
      }
      if (actual == enabled && mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFullscreenRejected,
          duration: _snackbarShortDuration,
        );
      }
      _log(
        'fullscreen_toggled',
        category: DebugLogCategory.ui,
        detailsBuilder: () => {'requested': !enabled, 'actual': actual},
      );
    } catch (e) {
      _log(
        'fullscreen_toggle_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    } finally {
      _fullscreenToggleInFlight = false;
    }
  }

  Future<void> _exitFullscreen() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        if (mounted) {
          setState(() {
            _isFullscreen = false;
            _fullscreenChromeHideTimer?.cancel();
            _fullscreenChromeVisible = true;
          });
        }
      } else if (mounted) {
        setState(() {
          _isFullscreen = false;
          _fullscreenChromeHideTimer?.cancel();
          _fullscreenChromeVisible = true;
        });
      }
    } catch (e) {
      _log(
        'fullscreen_exit_failed',
        category: DebugLogCategory.ui,
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shortcutFocus,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        endDrawer: _buildPlayQueueDrawer(),
        body: GlassShellBackground(
          child: Column(
            children: [
              if (_showPlayerChrome) const CustomTitleBar(),
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => _onDragEntered(),
                  onDragExited: (_) => _onDragExited(),
                  onDragDone: _onDragDone,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildMediaSurface(),
                            PlayerDragOverlay(visible: _isDragging),
                          ],
                        ),
                      ),
                      _showPlayerChrome
                          ? _buildBottomDock()
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDock() {
    return PlayerBottomDock(
      sleepTimer: _sleepTimer,
      advancedPlayback: _advancedPlayback,
      player: _player,
      settings: _settings,
      seekPreviewService: _seekPreviewService,
      hasMedia: _currentFile != null,
      onSeekStart: () => _player.isSeeking = true,
      onSeekChange: (value) {
        setState(() {
          _player.position = Duration(milliseconds: value.toInt());
        });
      },
      onSeekEnd: (value) {
        _player.isSeeking = false;
        unawaited(
          _playerService.seek(Duration(milliseconds: value.toInt())).catchError(
            (Object e) {
              _log(
                'seek_slider_failed',
                message: e.toString(),
                severity: DebugSeverity.warn,
              );
            },
          ),
        );
      },
      onPlayPause: () async {
        _log('control_play_pause_pressed', category: DebugLogCategory.ui);
        try {
          await _playerService.playPause();
        } catch (e) {
          _log(
            'control_play_pause_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }
      },
      onStop: () async {
        _log('control_stop_pressed', category: DebugLogCategory.ui);
        await _stopPlaybackAndResetUi();
      },
      onOpenFile: _openFile,
      onOpenFolder: () => unawaited(_openFolder()),
      onOpenUrl: () => unawaited(_openUrl()),
      onReopenLast: () {
        _log('control_reopen_last_pressed', category: DebugLogCategory.ui);
        unawaited(_reopenLastFile());
      },
      onVolumeChanged: (vol) async {
        _log(
          'control_volume_changed',
          category: DebugLogCategory.ui,
          detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
        );
        try {
          await _playerService.setVolume(vol);
          _settings.volume = vol;
        } catch (e) {
          _log(
            'control_volume_apply_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }
      },
      onLoopModeChanged: (mode) {
        _log(
          'control_loop_mode_changed',
          category: DebugLogCategory.ui,
          detailsBuilder: () => {'loop_mode': mode.name},
        );
        _settings.loopMode = mode;
      },
      onRecentFileSelected: _loadRecentFile,
      onSettingsPressed: _openSettings,
      onMoreActions: _showMoreMenu,
      onPrevious: () => unawaited(_advancePlaylist(-1)),
      onNext: () => unawaited(_advancePlaylist(1)),
      onToggleQueue: () => _scaffoldKey.currentState?.openEndDrawer(),
      onToggleMute: _toggleMute,
      onCycleSpeed: _cyclePlaybackSpeed,
    );
  }

  Widget _buildPlayQueueDrawer() {
    return PlayQueueDrawer(
      playlist: _playlist,
      hasCurrentFile: () => _currentFile != null,
      onShowMediaInfo: () => unawaited(_showMediaInfoDialog()),
      onSetShuffle: _setShuffle,
      onClearQueue: () => unawaited(_confirmClearQueue()),
      onActivateItem: (source) => unawaited(
        _loadSource(source, syncPlaylist: false, origin: SourceOrigin.queue),
      ),
      onRemoveItem: (index) => unawaited(_removeQueueItem(index)),
      onAddFiles: _pickFilesToEnqueue,
      onAddFolder: (playNow) => unawaited(_openFolder(playNow: playNow)),
      onOpenPlaylist: (playNow) =>
          unawaited(_openPlaylistPicker(playNow: playNow)),
      onSavePlaylist: () => unawaited(_exportPlaylistQueue()),
      onRemoveMissing: () => unawaited(_removeMissingQueueItems()),
    );
  }

  Widget _buildMediaSurface() {
    return MediaSurface(
      player: _player,
      settings: _settings,
      hasMedia: _currentFile != null,
      videoController: _videoController,
      mediaDisplayTitle: _mediaDisplayTitle,
      mediaDisplayArtist: _mediaDisplayArtist,
      compactMode: _compactMode,
      isFullscreen: _isFullscreen,
      fullscreenChromeVisible: _fullscreenChromeVisible,
      onTap: () {
        _restoreShortcutFocus(refocusNativeWindow: false);
        _revealFullscreenChrome();
        unawaited(
          _playerService.playPause().catchError((Object e) {
            _log(
              'media_surface_tap_play_pause_failed',
              category: DebugLogCategory.ui,
              message: e.toString(),
              severity: DebugSeverity.warn,
            );
          }),
        );
      },
      onDoubleTap: () {
        _log('media_surface_double_tap', category: DebugLogCategory.ui);
        unawaited(_toggleFullscreen());
      },
      onHover: () {
        _pulseOsd();
        _revealFullscreenChrome();
      },
      onScrollVolume: (scrollDeltaY, timeStamp) {
        if (_currentFile == null) return;
        _revealFullscreenChrome();
        final step = _scrollVolume.add(scrollDeltaY, timeStamp);
        if (step != 0) _adjustVolume(step);
      },
      onExitCompactMode: () => unawaited(_toggleCompactMode()),
      onDismissEmptyStateTip: () => setState(() {
        _settings.emptyStateTipDismissed = true;
      }),
      onOpenFile: _openFile,
      onOpenFolder: () => unawaited(_openFolder()),
      onOpenPlaylist: () => unawaited(_openPlaylistPicker()),
      onOpenUrl: () => unawaited(_openUrl()),
      onReopenLast: _reopenLastFile,
    );
  }

  // ── OSD ────────────────────────────────────────────────────

  void _pulseOsd() => _messenger.pulseOsd();

  void _showOsdMessage(String msg) => _messenger.showOsdMessage(msg);

  // ── Tracks: audio / subtitle cycling ──────────────────────

  Future<void> _cycleAudioTrack() async {
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    if (tracks == null || tracks.audio.length <= 1) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (!TrackCyclePolicy.canCycle(selectableCount: list.length)) return;
    final current = _player.currentTrackSelection?.audio.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next =
        list[TrackCyclePolicy.nextIndex(
          currentIndex: idx,
          listLength: list.length,
        )];
    await _disableMixForManualTrackSelection();
    final ok = await _playerService.setAudioTrack(next);
    if (!ok) return;
    _showOsdMessage(
      l10n.osdAudioTrack(_trackLabel(next.title, next.language, next.id)),
    );
  }

  Future<void> _cycleSubtitleTrack() async {
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    if (list.length <= 1) return;
    final current = _player.currentTrackSelection?.subtitle.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next =
        list[TrackCyclePolicy.nextIndex(
          currentIndex: idx,
          listLength: list.length,
        )];
    final ok = await _playerService.setSubtitleTrack(next);
    if (!ok) return;
    _player.subtitlesVisible = next.id != 'no';
    _showOsdMessage(
      next.id == 'no'
          ? l10n.osdSubtitlesOff
          : l10n.osdSubtitlesTrack(
              _trackLabel(next.title, next.language, next.id),
            ),
    );
  }

  Future<void> _toggleSubtitleVisibility() async {
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    if (_player.subtitlesVisible) {
      final ok = await _playerService.setSubtitleTrack(SubtitleTrack.no());
      if (!ok) return;
      _player.subtitlesVisible = false;
      _showOsdMessage(l10n.osdSubtitlesOff);
    } else {
      final candidate = tracks.subtitle.firstWhere(
        (t) => t.id != 'no' && t.id != 'auto',
        orElse: SubtitleTrack.auto,
      );
      final ok = await _playerService.setSubtitleTrack(candidate);
      if (!ok) return;
      _player.subtitlesVisible = true;
      _showOsdMessage(
        l10n.osdSubtitlesTrack(
          _trackLabel(candidate.title, candidate.language, candidate.id),
        ),
      );
    }
  }

  String _trackLabel(String? title, String? language, String fallbackId) =>
      formatTrackLabel(
        title: title,
        language: language,
        fallbackId: fallbackId,
        fallbackLabel: AppLocalizations.of(context)
            .trackFallbackLabel(fallbackId),
      );

  // ── Chapters ──────────────────────────────────────────────

  Future<void> _refreshChapters({int? expectedCount, int? gen}) async {
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final l10n = AppLocalizations.of(context);
    final list = await ChapterListLoader.load(
      readProperty: _playerService.getProperty,
      expectedCount: expectedCount,
      fallbackTitle: (i) => l10n.chapterFallbackLabel(i + 1),
    );
    if (!mounted || (gen != null && !_playback.isLoadCurrent(gen))) return;
    setState(() => _player.chapters = list);
  }

  Future<void> _stepChapter(int delta) async {
    final l10n = AppLocalizations.of(context);
    if (_player.chapters.isEmpty) {
      await _refreshChapters();
    }
    if (_player.chapters.isEmpty) return;
    final current = await _playerService.getProperty('chapter');
    final idx = int.tryParse(current ?? '') ?? 0;
    final next = ChapterNavigationPolicy.stepIndex(
      currentIndex: idx,
      delta: delta,
      chapterCount: _player.chapters.length,
    );
    final ok = await _playerService.setChapter(next);
    if (!ok) return;
    _showOsdMessage(l10n.osdChapter(_player.chapters[next].title));
  }

  // ── Screenshot ────────────────────────────────────────────

  Future<void> _takeScreenshot() async {
    final l10n = AppLocalizations.of(context);
    try {
      final source = _player.currentSource;
      if (source == null) return;
      final configuredDirectory = _settings.screenshotDir;
      final customDirectory =
          configuredDirectory != null &&
              await PathProbe.directoryExists(configuredDirectory)
          ? configuredDirectory
          : null;
      final saver = ScreenshotSaver(
        capture: (mime) => _playerService.screenshot(format: mime),
        resolveScope: _resolveBookmarkScope,
        releaseScope: BookmarkService.stop,
      );
      final result = await saver.save(
        source: source,
        format: _settings.screenshotFormat,
        customDirectory: customDirectory,
      );
      switch (result.outcome) {
        case ScreenshotSaveOutcome.noFrame:
          _showOsdMessage(l10n.osdScreenshotFailed);
        case ScreenshotSaveOutcome.directoryUnavailable:
          _log(
            'screenshot_dir_create_failed',
            message: result.error.toString(),
            details: {'dir': result.directory},
            severity: DebugSeverity.warn,
          );
          if (mounted) {
            showAppSnackBar(context, l10n.snackScreenshotDirInaccessible);
          }
          _showOsdMessage(l10n.osdScreenshotSaveFailed);
        case ScreenshotSaveOutcome.saved:
          _showOsdMessage(l10n.osdScreenshotSaved);
          _log('screenshot_saved', detailsBuilder: () => {'path': result.path});
        case ScreenshotSaveOutcome.writeFailed:
          _showOsdMessage(l10n.osdScreenshotSaveFailed);
          _log(
            'screenshot_save_failed',
            message: result.error.toString(),
            severity: DebugSeverity.warn,
          );
      }
    } finally {
      final done = widget.screenshotOperationForTesting;
      if (done != null && !done.isCompleted) {
        done.complete();
      }
    }
  }

  Directory _mediaSessionArtDirectory() {
    if (LinuxInstallDetector.isFlatpak) {
      final cacheHome = Platform.environment['XDG_CACHE_HOME'];
      final home = Platform.environment['HOME'];
      if (cacheHome != null && cacheHome.startsWith('/')) {
        return Directory(p.join(cacheHome, 'dacx-media-session'));
      }
      if (home != null && home.startsWith('/')) {
        return Directory(
          p.join(
            home,
            '.var',
            'app',
            'run.rosie.dacx',
            'cache',
            'dacx-media-session',
          ),
        );
      }
    }
    if (Platform.isLinux) {
      // Linux `/tmp` is shared between users; a fixed folder there can be
      // pre-created and seeded with symlinks. Use the per-user cache instead.
      final cacheHome = Platform.environment['XDG_CACHE_HOME'];
      if (cacheHome != null && cacheHome.startsWith('/')) {
        return Directory(p.join(cacheHome, 'dacx', 'media-session'));
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.startsWith('/')) {
        return Directory(p.join(home, '.cache', 'dacx', 'media-session'));
      }
    }
    // macOS and Windows temp folders are already per-user.
    return Directory(p.join(Directory.systemTemp.path, 'dacx-media-session'));
  }

  // ── Equalizer ─────────────────────────────────────────────

  Future<void> _applyEqualizer() async {
    await _applyMergedAudioFilters();
  }

  /// Builds and applies the EQ af chain.
  Future<void> _applyMergedAudioFilters({int? gen}) async {
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final result = await _audioSession.applyMergedAudioFilters();
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    if (result.failed) {
      _log(
        'audio_filter_apply_failed',
        detailsBuilder: () => {'chain': result.appliedChain},
        severity: DebugSeverity.warn,
      );
    }
  }

  void _toggleEqualizer() {
    final wantEnabled = !_settings.eqEnabled;
    _settings.eqEnabled = wantEnabled;
    unawaited(() async {
      final result = await _audioSession.applyMergedAudioFilters();
      if (!mounted || _isDisposed) return;
      final l10n = AppLocalizations.of(context);
      if (result.failed) {
        _settings.eqEnabled = !wantEnabled;
        _showOsdMessage(l10n.osdEqualizer(l10n.osdStateOff));
        showAppSnackBar(
          context,
          l10n.snackPlaybackOperationFailed('equalizer'),
        );
        return;
      }
      _showOsdMessage(
        l10n.osdEqualizer(wantEnabled ? l10n.osdStateOn : l10n.osdStateOff),
      );
    }());
  }

  // ── Multi-audio mix ───────────────────────────────────────

  /// Applies or clears the multi-audio `lavfi-complex` graph.
  ///
  /// Returns `true` when the requested state was applied (including a clean
  /// disable). Returns `false` when enable was requested but failed; in that
  /// case the Experimental mix toggle is turned back off and the user gets
  /// OSD + snackbar feedback.
  Future<bool> _applyMultiAudioMix({bool announce = false, int? gen}) async {
    if (gen != null && !_playback.isLoadCurrent(gen)) return true;
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    // No open media yet; keep the preference for the next multi-track file.
    if (tracks == null) return true;
    final ids = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .toList(growable: false);
    final shouldMix = _settings.multiAudioMix && ids.length >= 2;
    if (!shouldMix) {
      // Always clear the property in case a previous file left a graph.
      await _playerService.setProperty('lavfi-complex', '');
      if (gen != null && !_playback.isLoadCurrent(gen)) return true;
      if (_player.mixActive) {
        _player.mixActive = false;
        if (announce) {
          _showOsdMessage(l10n.osdAudioMixOff);
        }
      }
      return true;
    }
    // Validate IDs are numeric; mpv's lavfi-complex labels are [aid<N>]
    // where <N> must be the integer track-id reported in track-list.
    final invalid = ids.where((id) => int.tryParse(id) == null).toList();
    if (invalid.isNotEmpty) {
      _log(
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
    _log(
      'multi_audio_mix_apply',
      detailsBuilder: () => {
        'track_count': ids.length,
        'track_ids': ids.join(','),
        'chain': chain,
      },
    );
    final ok = await _playerService.setProperty('lavfi-complex', chain);
    if (gen != null && !_playback.isLoadCurrent(gen)) return true;
    if (ok) {
      final wasActive = _player.mixActive;
      _player.mixActive = true;
      if (announce || !wasActive) {
        _showOsdMessage(l10n.osdAudioMixActive(ids.length));
      }
      return true;
    }
    _log('multi_audio_mix_setproperty_failed', severity: DebugSeverity.warn);
    await _revertMultiAudioMixFailure(l10n.osdAudioMixFailed);
    return false;
  }

  Future<void> _revertMultiAudioMixFailure(String message) async {
    _player.mixActive = false;
    if (_settings.multiAudioMix) {
      _settings.multiAudioMix = false;
    }
    await _playerService.setProperty('lavfi-complex', '');
    if (!mounted || _isDisposed) return;
    _showOsdMessage(message);
    showAppSnackBar(context, message);
  }

  Future<void> _reloadCurrentForMixChange() async {
    final source = _player.currentSource;
    if (source == null) return;
    if (_mixReloadInFlight) return;
    _mixReloadInFlight = true;
    try {
      final savedPos = _player.position;
      await _loadSource(
        source,
        syncPlaylist: false,
        applyResume: false,
        origin: SourceOrigin.queue,
      );
      if (savedPos > Duration.zero) {
        await Future<void>.delayed(_mixReloadDelay);
        if (mounted && !_isDisposed && _player.currentSource == source) {
          unawaited(_playerService.seek(savedPos));
        }
      }
    } finally {
      _mixReloadInFlight = false;
    }
  }

  Future<void> _disableMixForManualTrackSelection() async {
    if (!_settings.multiAudioMix && !_player.mixActive) return;
    final wasActive = _player.mixActive;
    if (_settings.multiAudioMix) {
      _settings.multiAudioMix = false;
    }
    await _playerService.setProperty('lavfi-complex', '');
    _player.mixActive = false;
    if (wasActive) {
      await _reloadCurrentForMixChange();
    }
  }

  // ── Media session command bridge ──────────────────────────

  void _deferMediaSessionSetting(void Function() apply) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      apply();
    });
  }

  void _syncIdleInhibit() {
    unawaited(
      _idleInhibit.setPlaying(
        _player.isPlaying,
        hasVideo: !_player.isAudioFile,
      ),
    );
  }

  void _onMediaSessionCommand(MediaSessionCommand cmd) {
    final dispatch = MediaSessionCommandDispatch.resolve(
      cmd,
      position: _player.position,
      duration: _player.duration,
    );
    switch (dispatch.kind) {
      case MediaSessionDispatchKind.play:
        unawaited(_playerService.play());
      case MediaSessionDispatchKind.pause:
        unawaited(_playerService.pause());
      case MediaSessionDispatchKind.toggle:
        unawaited(_playerService.playPause());
      case MediaSessionDispatchKind.stop:
        unawaited(_stopPlaybackAndResetUi());
      case MediaSessionDispatchKind.next:
        unawaited(_advancePlaylist(1));
      case MediaSessionDispatchKind.previous:
        unawaited(_advancePlaylist(-1));
      case MediaSessionDispatchKind.seek:
        final target = dispatch.seekTarget;
        if (target != null) {
          unawaited(_playerService.seek(target));
        }
      case MediaSessionDispatchKind.setLoopMode:
        final mode = dispatch.loopMode;
        if (mode != null) {
          _deferMediaSessionSetting(() => _settings.loopMode = mode);
        }
      case MediaSessionDispatchKind.setShuffle:
        final on = dispatch.shuffle;
        if (on != null) {
          _deferMediaSessionSetting(() => _setShuffle(on));
        }
      case MediaSessionDispatchKind.setVolume:
        final pct = dispatch.volumePercent;
        if (pct != null) {
          _deferMediaSessionSetting(() {
            setState(() {
              _player.volume = pct;
            });
            _settings.volume = pct;
            unawaited(_playerService.setVolume(pct).catchError((_) {}));
          });
        }
      case MediaSessionDispatchKind.setRate:
        final rate = dispatch.rate;
        if (rate != null) {
          _deferMediaSessionSetting(() => _settings.speed = rate);
        }
      case MediaSessionDispatchKind.raise:
        unawaited(windowManager.show().catchError((_) {}));
        unawaited(windowManager.focus().catchError((_) {}));
      case MediaSessionDispatchKind.quit:
        final onQuit = widget.onQuitRequest;
        if (onQuit != null) {
          unawaited(onQuit());
        } else {
          unawaited(() async {
            await AppExitHooks.runAll();
            if (_isDisposed) return;
            try {
              await windowManager.setPreventClose(false);
            } catch (_) {}
            await windowManager.destroy().catchError((_) {});
          }());
        }
      case MediaSessionDispatchKind.noop:
        break;
    }
  }

  Future<void> _stopPlaybackAndResetUi() async {
    _stopInProgress = true;
    _playback.beginLoad();
    try {
      await _playback.loadQueue.enqueue(
        () async {
          if (_isDisposed) return;
          _playback.beginLoad();
          _persistResumePosition();
          await _playerService.setProperty('lavfi-complex', '');
          _player.mixActive = false;
          await _playerService.stop();
          await _advancedPlayback.setSource(null);
          unawaited(_seekPreviewService.setSource(null));
          unawaited(_mediaSession.clear());
          if (!mounted || _isDisposed) return;
          setState(() {
            _player.clearMediaSurface();
            _mediaDisplayTitle = null;
            _mediaDisplayArtist = null;
          });
        },
        onError: (Object e, StackTrace st) {
          _log(
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

  // ── Resume position ─────────────────────────────────

  void _persistResumePosition({bool requirePlaying = false}) {
    if (!_settings.resumePlaybackEnabled) return;
    if (requirePlaying && !_player.isPlaying) return;
    final path = _player.resumePathInProgress;
    if (path == null) return;
    final action = ResumePlaybackPolicy.persistAction(
      position: _player.position,
      duration: _player.duration,
    );
    switch (action) {
      case ResumePersistAction.skip:
        return;
      case ResumePersistAction.clear:
        _settings.saveResumePosition(path, null);
      case ResumePersistAction.save:
        _settings.saveResumePosition(path, _player.position.inMilliseconds);
    }
  }

  Future<void> _maybeApplyResume(String path, {int? gen}) async {
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    final l10n = AppLocalizations.of(context);
    final ms = _settings.resumePositionFor(path);
    var action = ResumePlaybackPolicy.applyAction(
      resumeMs: ms,
      durationMs: _player.duration.inMilliseconds,
    );
    for (
      var i = 0;
      i < ResumePlaybackPolicy.durationPollAttempts &&
          action == ResumeApplyAction.waitForDuration;
      i++
    ) {
      await Future<void>.delayed(_durationPollInterval);
      if (_isDisposed ||
          _currentFile != path ||
          (gen != null && !_playback.isLoadCurrent(gen))) {
        return;
      }
      action = ResumePlaybackPolicy.applyAction(
        resumeMs: ms,
        durationMs: _player.duration.inMilliseconds,
      );
    }
    switch (action) {
      case ResumeApplyAction.skip:
      case ResumeApplyAction.waitForDuration:
        return;
      case ResumeApplyAction.clearStored:
        _settings.saveResumePosition(path, null);
        return;
      case ResumeApplyAction.seek:
        break;
    }
    if (gen != null && !_playback.isLoadCurrent(gen)) return;
    try {
      await _playerService.seek(Duration(milliseconds: ms!));
      if (mounted && (gen == null || _playback.isLoadCurrent(gen))) {
        _showOsdMessage(
          l10n.osdResumedAt(
            ResumePlaybackPolicy.formatHms(Duration(milliseconds: ms)),
          ),
        );
      }
    } catch (e) {
      _log(
        'resume_seek_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  // ── Playlist ────────────────────────────────────────

  Future<void> _advancePlaylist(int delta) async {
    if (_playlist.isEmpty) return;
    await _playback.loadQueue.enqueue(
      () async {
        if (_isDisposed || _playlist.isEmpty) return;
        final wrap = PlaylistAdvancePolicy.shouldWrapQueue(_settings.loopMode);
        final next = _playlist.advance(delta, wrap: wrap);
        if (next == null) return;
        final l10n = AppLocalizations.of(context);
        _showOsdMessage(
          delta > 0 ? l10n.osdNextInQueue : l10n.osdPreviousInQueue,
        );
        await _loadSourceInternal(
          next,
          syncPlaylist: false,
          origin: SourceOrigin.queue,
        );
      },
      onError: (Object e, StackTrace st) {
        _log(
          'load_queue_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      },
    );
  }

  void _enqueue(
    List<String> paths, {
    bool playNow = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    _enqueueSources(
      paths.map(PlayableSource.file).toList(growable: false),
      playNow: playNow,
      origin: origin,
    );
  }

  void _enqueueSources(
    List<PlayableSource> sources, {
    bool playNow = false,
    SourceOrigin origin = SourceOrigin.other,
  }) {
    if (sources.isEmpty) return;
    switch (EnqueuePolicy.mode(
      playNow: playNow,
      playlistEmpty: _playlist.isEmpty,
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
          _playback.loadQueue.enqueue(() async {
            var openedIndex = -1;
            final failureBatch = candidates.length > 1
                ? _LoadFailureBatch()
                : null;
            try {
              for (var i = 0; i < attemptLimit; i++) {
                if (_isDisposed) return;
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
            if (openedIndex < 0 || _isDisposed) return;
            final dropped = _playlist.replaceSources(
              candidates,
              startIndex: openedIndex,
            );
            if (dropped > 0 && mounted) {
              showAppSnackBar(
                context,
                AppLocalizations.of(
                  context,
                ).snackQueueTruncated(PlaylistService.maxQueueItems, dropped),
              );
            }
          }),
        );
      case EnqueueMode.append:
        final dropped = _playlist.addAllSources(sources);
        _showOsdMessage(
          sources.length == 1
              ? AppLocalizations.of(context).osdAddedToQueue
              : AppLocalizations.of(context)
                    .osdAddedMultipleToQueue(sources.length),
        );
        if (dropped > 0 && mounted) {
          showAppSnackBar(
            context,
            AppLocalizations.of(context)
                .snackQueueTruncated(PlaylistService.maxQueueItems, dropped),
          );
        }
    }
  }

  Future<void> _confirmClearQueue() async {
    if (_playlist.isEmpty) return;
    final confirmed = await showClearQueueConfirmation(context);
    if (confirmed != true || !mounted) return;
    final wasPlaying = _currentFile != null;
    _playlist.clear();
    if (wasPlaying) {
      await _stopPlaybackAndResetUi();
    }
  }

  Future<void> _removeMissingQueueItems() async {
    var currentRemoved = false;
    final removed = await _playlist.removeMissingFiles(
      onCurrentRemoved: () => currentRemoved = true,
    );
    if (!mounted) return;
    if (_playlist.isEmpty) {
      unawaited(_stopPlaybackAndResetUi());
    } else if (currentRemoved) {
      final next = _playlist.current;
      if (next != null) {
        unawaited(
          _loadSource(next, syncPlaylist: false, origin: SourceOrigin.queue),
        );
      }
    }
    showAppSnackBar(
      context,
      AppLocalizations.of(context).snackQueueRemovedMissing(removed),
    );
  }

  Future<void> _removeQueueItem(int index) async {
    final wasCurrent = index == _playlist.index;
    _playlist.removeAt(index);
    if (!wasCurrent) return;
    final next = _playlist.current;
    if (next == null) {
      await _stopPlaybackAndResetUi();
      return;
    }
    await _loadSource(next, syncPlaylist: false, origin: SourceOrigin.queue);
  }

  // ── Compact / mini-player mode ────────────────────────────

  Future<void> _toggleCompactMode() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (_compactToggleInFlight) return;
    _compactToggleInFlight = true;
    try {
      final l10n = AppLocalizations.of(context);
      if (_compactMode) {
        // Restore window state.
        try {
          if (_preCompactMaximized) {
            await windowManager.maximize();
          } else {
            if (_preCompactSize != null) {
              await windowManager.setSize(_preCompactSize!);
            }
            if (_preCompactPos != null) {
              await windowManager.setPosition(_preCompactPos!);
            }
          }
          await windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
        } catch (e) {
          _log(
            'compact_mode_restore_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
          return;
        }
        if (!mounted || _isDisposed) return;
        setState(() => _compactMode = false);
        widget.onCompactModeChanged?.call(false);
        _showOsdMessage(l10n.osdMiniPlayerOff);
      } else {
        try {
          final size = await windowManager.getSize();
          final position = await windowManager.getPosition();
          final maximized = await windowManager.isMaximized();
          if (await windowManager.isFullScreen()) {
            await windowManager.setFullScreen(false);
            if (mounted) {
              _isFullscreen = false;
            }
          }
          if (maximized) {
            await windowManager.unmaximize();
          }
          await windowManager.setSize(_compactWindowSize);
          await windowManager.setAlwaysOnTop(true);
          _preCompactSize = size;
          _preCompactPos = position;
          _preCompactMaximized = maximized;
        } catch (e) {
          _log(
            'compact_mode_enter_failed',
            category: DebugLogCategory.ui,
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
          return;
        }
        if (!mounted || _isDisposed) return;
        setState(() => _compactMode = true);
        widget.onCompactModeChanged?.call(true);
        _showOsdMessage(l10n.osdMiniPlayerOn);
      }
    } finally {
      _compactToggleInFlight = false;
    }
  }

  // ── Media info ────────────────────────────────────────────

  Future<void> _showMediaInfoDialog() async {
    final source = _player.currentSource;
    if (source == null) return;
    if (_player.chapters.isEmpty) {
      await _refreshChapters();
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final width = await _playerService.getProperty('width');
    final height = await _playerService.getProperty('height');
    String? metaTitle;
    String? metaArtist;
    String? metaAlbum;
    try {
      metaTitle = await _playerService.getProperty('metadata/by-key/title');
      metaArtist = await _playerService.getProperty('metadata/by-key/artist');
      metaAlbum = await _playerService.getProperty('metadata/by-key/album');
    } catch (_) {
      // Best-effort tags; fall back to cached display fields / unknown.
    }
    if (!mounted) return;
    final tracks = _player.currentTracks;
    final audioTracks =
        tracks?.audio.where((t) => t.id != 'auto' && t.id != 'no').length ?? 0;
    final subtitleTracks =
        tracks?.subtitle.where((t) => t.id != 'auto' && t.id != 'no').length ??
        0;
    final audioSelection = _player.currentTrackSelection?.audio;
    final subtitleSelection = _player.currentTrackSelection?.subtitle;
    final resolution =
        (width != null &&
            height != null &&
            width.trim().isNotEmpty &&
            height.trim().isNotEmpty)
        ? '${width.trim()} × ${height.trim()}'
        : l10n.mediaInfoUnknown;
    final type = source.isUrl
        ? l10n.mediaInfoTypeUrlStream
        : (_player.isAudioFile
              ? l10n.mediaInfoTypeAudioFile
              : l10n.mediaInfoTypeVideoFile);
    final titleValue = () {
      final fromMeta = metaTitle?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      final cached = _mediaDisplayTitle?.trim();
      if (cached != null && cached.isNotEmpty) return cached;
      return source.displayName;
    }();
    final artistValue = () {
      final fromMeta = metaArtist?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      final cached = _mediaDisplayArtist?.trim();
      if (cached != null && cached.isNotEmpty) return cached;
      return l10n.mediaInfoUnknown;
    }();
    final albumValue = () {
      final fromMeta = metaAlbum?.trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
      return l10n.mediaInfoUnknown;
    }();

    await showDialog<void>(
      context: context,
      builder: (ctx) => MediaInfoDialog(
        width: dialogWidth(ctx, 520),
        fields: [
          MediaInfoField(label: l10n.mediaInfoTitle, value: titleValue),
          MediaInfoField(label: l10n.mediaInfoArtist, value: artistValue),
          MediaInfoField(label: l10n.mediaInfoAlbum, value: albumValue),
          MediaInfoField(
            label: l10n.mediaInfoSource,
            value: source.isUrl
                ? PlayableSource.displaySafeUrl(source.value)
                : source.value,
          ),
          MediaInfoField(label: l10n.mediaInfoType, value: type),
          MediaInfoField(
            label: l10n.mediaInfoDuration,
            value: _player.duration.inMilliseconds > 0
                ? PlayerController.formatDuration(_player.duration)
                : l10n.mediaInfoUnknown,
          ),
          MediaInfoField(label: l10n.mediaInfoResolution, value: resolution),
          MediaInfoField(
            label: l10n.mediaInfoAudioTracks,
            value: '$audioTracks',
          ),
          MediaInfoField(
            label: l10n.mediaInfoSubtitleTracks,
            value: '$subtitleTracks',
          ),
          MediaInfoField(
            label: l10n.mediaInfoChapters,
            value: '${_player.chapters.length}',
          ),
          MediaInfoField(
            label: l10n.mediaInfoAudioSelection,
            value: audioSelection == null
                ? l10n.mediaInfoUnknown
                : _trackLabel(
                    audioSelection.title,
                    audioSelection.language,
                    audioSelection.id,
                  ),
          ),
          MediaInfoField(
            label: l10n.mediaInfoSubtitleSelection,
            value: subtitleSelection == null || subtitleSelection.id == 'no'
                ? l10n.mediaInfoUnknown
                : _trackLabel(
                    subtitleSelection.title,
                    subtitleSelection.language,
                    subtitleSelection.id,
                  ),
          ),
        ],
      ),
    );
  }

  // ── More menu ─────────────────────────────────────────────

  Future<void> _showMoreMenu() async {
    final tracks = _player.currentTracks;
    final hasAudioOptions = tracks != null && tracks.audio.length > 1;
    final hasSubOptions = tracks != null && tracks.subtitle.isNotEmpty;
    if (_player.chapters.isEmpty) await _refreshChapters();
    if (!mounted) return;
    final hasChapters = _player.chapters.isNotEmpty;

    final result = await showPlayerMoreMenuSheet(
      context: context,
      hasAudioOptions: hasAudioOptions,
      hasSubOptions: hasSubOptions,
      hasChapters: hasChapters,
      hasCurrentFile: () => _currentFile != null,
      compactMode: () => _compactMode,
      settings: _settings,
      sleepTimer: _sleepTimer,
      playlist: _playlist,
      onSetShuffle: _setShuffle,
    );
    if (!mounted) return;
    dispatchPlayerMoreMenuResult(
      result,
      PlayerMoreMenuActions(
        onOpenUrl: () => unawaited(_openUrl()),
        onAudioTracks: () => unawaited(_showAudioTracksDialog()),
        onSubtitleTracks: () => unawaited(_showSubtitleTracksDialog()),
        onExternalAudio: () => unawaited(_pickExternalAudio()),
        onExternalSubtitle: () => unawaited(_pickExternalSubtitle()),
        onChapters: () => unawaited(_showChaptersDialog()),
        onEqualizer: () => unawaited(
          showEqualizerDialog(
            context: context,
            settings: _settings,
            onApply: _applyEqualizer,
          ),
        ),
        onAdvancedPlayback: () => unawaited(_showAdvancedPlaybackDialog()),
        onScreenshot: () => unawaited(_takeScreenshot()),
        onSleepTimer: _setSleepTimerMinutes,
        onKeybinds: () => unawaited(
          showKeybindsDialog(context: context, settings: _settings),
        ),
        onQueue: () => _scaffoldKey.currentState?.openEndDrawer(),
        onEnqueue: () => unawaited(_pickFilesToEnqueue()),
        onSetShuffle: _setShuffle,
        onCompact: () => unawaited(_toggleCompactMode()),
      ),
    );
  }

  Future<void> _showAdvancedPlaybackDialog() async {
    if (!_settings.advancedPlaybackToolsEnabled) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AdvancedPlaybackDialog(
        controller: _advancedPlayback,
        settings: _settings,
      ),
    );
  }

  Future<void> _pickExternalAudio() async {
    final l10n = AppLocalizations.of(context);
    try {
      final path = await _pickers.pickExternalAudioFile();
      if (path == null) return;
      await _captureBookmarkFor(path);
      final ok = await _playerService.addExternalAudio(
        path,
        allowUnc: SourceOrigin.fileDialog.allowsUnc,
      );
      if (!mounted) return;
      _showOsdMessage(
        ok ? l10n.osdExternalAudioLoaded : l10n.osdExternalAudioFailed,
      );
      if (ok) {
        _cacheTracksForCurrentLoad(_playerService.currentTracks);
        setState(() {});
      } else {
        showAppSnackBar(context, l10n.osdExternalAudioFailed);
      }
    } catch (e) {
      _log(
        'external_audio_pick_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        _showOsdMessage(l10n.osdExternalAudioFailed);
        showAppSnackBar(context, l10n.osdExternalAudioFailed);
      }
    }
  }

  Future<void> _pickExternalSubtitle() async {
    final l10n = AppLocalizations.of(context);
    try {
      final path = await _pickers.pickExternalSubtitleFile();
      if (path == null) return;
      await _captureBookmarkFor(path);
      final ok = await _playerService.addExternalSubtitle(
        path,
        allowUnc: SourceOrigin.fileDialog.allowsUnc,
      );
      if (!mounted) return;
      _showOsdMessage(
        ok ? l10n.osdExternalSubtitleLoaded : l10n.osdExternalSubtitleFailed,
      );
      if (ok) {
        _cacheTracksForCurrentLoad(_playerService.currentTracks);
        setState(() {});
      } else {
        showAppSnackBar(context, l10n.osdExternalSubtitleFailed);
      }
    } catch (e) {
      _log(
        'external_subtitle_pick_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        _showOsdMessage(l10n.osdExternalSubtitleFailed);
        showAppSnackBar(context, l10n.osdExternalSubtitleFailed);
      }
    }
  }

  Future<void> _showAudioTracksDialog() async {
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    final selected = await pickAudioTrack(
      context,
      tracks: list,
      currentId: _player.currentTrackSelection?.audio.id,
    );
    if (selected != null) {
      await _disableMixForManualTrackSelection();
      final ok = await _playerService.setAudioTrack(selected);
      if (!ok && mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context)
              .snackPlaybackOperationFailed(selected.id),
        );
      }
    }
  }

  Future<void> _showSubtitleTracksDialog() async {
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    final selected = await pickSubtitleTrack(
      context,
      tracks: list,
      currentId: _player.currentTrackSelection?.subtitle.id,
    );
    if (selected != null) {
      final ok = await _playerService.setSubtitleTrack(selected);
      if (!ok) return;
      _player.subtitlesVisible = selected.id != 'no';
    }
  }

  Future<void> _showChaptersDialog() async {
    if (_player.chapters.isEmpty) await _refreshChapters();
    if (!mounted || _player.chapters.isEmpty) return;
    final picked = await pickChapter(context, _player.chapters);
    if (picked != null) {
      await _playerService.setChapter(picked);
    }
  }

  Future<void> _pickFilesToEnqueue() async {
    try {
      final paths = await _pickers.pickFilesToEnqueue();
      if (paths.isEmpty) return;
      final sources = <PlayableSource>[];
      for (final path in paths) {
        await _captureBookmarkFor(path);
        if (M3uPlaylist.isPlaylistPath(path)) {
          try {
            sources.addAll(await M3uPlaylist.parseFile(path));
          } catch (e) {
            _log(
              'enqueue_playlist_parse_failed',
              message: e.toString(),
              detailsBuilder: () => {'path': path},
              severity: DebugSeverity.warn,
            );
          }
        } else {
          sources.add(PlayableSource.file(path));
        }
      }
      _pickers.rememberLastOpenDirectory(paths.first);
      if (sources.isEmpty) {
        if (mounted) {
          showAppSnackBar(
            context,
            AppLocalizations.of(context).snackPlaylistEmptyOrInvalid,
          );
        }
        return;
      }
      _enqueueSources(sources, origin: SourceOrigin.fileDialog);
    } on PlatformException catch (e) {
      _log(
        'enqueue_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        final rawDetail = e.message?.trim();
        final detail = rawDetail == null || rawDetail.isEmpty
            ? e.code
            : rawDetail;
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackFilePickerFailed(detail),
        );
      }
    } catch (e) {
      _log(
        'enqueue_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          AppLocalizations.of(context).snackUnableToOpenFilePicker,
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
