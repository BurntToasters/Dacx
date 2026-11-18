import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../services/player_service.dart';
import '../services/advanced_playback_controller.dart';
import '../services/app_exit_hooks.dart';
import '../services/settings_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/idle_inhibit_service.dart';
import '../services/debug_log_service.dart';
import '../services/media_session_service.dart';
import '../services/packaged_e2e_probe.dart';
import '../services/playlist_service.dart';
import '../services/open_file_bridge.dart';
import '../services/seek_preview_service.dart';
import '../models/chapter_info.dart';
import '../models/playable_source.dart';
import '../l10n/app_localizations.dart';
import '../theme/glass_decorations.dart';
import '../services/update_service.dart';
import '../playback/playback_controller.dart';
import '../playback/player_path_utils.dart';
import '../playback/player_audio_session.dart';
import '../playback/player_controller.dart';
import '../playback/sleep_timer_controller.dart';
import '../playback/playlist_advance_policy.dart';
import '../playback/source_load_validation_policy.dart';
import '../playback/volume_policy.dart';
import '../playback/subscription_bag.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/keybinds_dialog.dart';
import 'player/media_session_coordinator.dart';
import 'player/player_file_pickers.dart';
import 'player/player_media_info.dart';
import 'player/player_menu_bridge.dart';
import 'player/player_messenger.dart';
import 'player/player_more_menu_controller.dart';
import 'player/player_open_actions.dart';
import 'player/player_screenshot_action.dart';
import 'player/player_settings_route.dart';
import 'player/player_transport_controller.dart';
import 'player/player_update_notice.dart';
import 'player/player_settings_applier.dart';
import 'player/player_shortcut_actions.dart';
import 'player/player_shortcut_dispatcher.dart';
import 'player/player_window_controller.dart';
import 'player/source_load_coordinator.dart';
import 'player/track_chapter_controller.dart';
import 'player/widgets/drag_overlay.dart';
import 'player/widgets/fullscreen_chrome_overlay.dart';
import 'player/widgets/media_surface.dart';
import 'player/widgets/mini_player_layout.dart';
import 'player/widgets/player_bottom_dock.dart';
import 'player/widgets/play_queue_drawer.dart';

const _resumeSaveInterval = Duration(seconds: 5);
const _snackbarShortDuration = Duration(seconds: 2);

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
  final GlobalKey _mediaStackKey = GlobalKey();
  late final PlayerShortcutDispatcher _shortcuts = PlayerShortcutDispatcher(
    settings: _settings,
    isActive: () => mounted && !_isDisposed,
    routeIsCurrent: _playerRouteIsCurrent,
    hasMedia: () => _currentFile != null,
    isEndDrawerOpen: () => _scaffoldKey.currentState?.isEndDrawerOpen ?? false,
    onEscape: _handleEscapeBack,
    onShowHelp: () =>
        unawaited(showKeybindsDialog(context: context, settings: _settings)),
    onAction: (action) => _shortcutActions.handle(action),
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

  bool _isDisposed = false;
  final _scrollVolume = ScrollVolumeAccumulator();

  // Tracks / chapters / OSD state
  late final PlayerFilePickers _pickers = PlayerFilePickers(
    settings: _settings,
    restoreFocus: _shortcuts.restoreFocus,
  );
  late final PlayerMessenger _messenger = PlayerMessenger(
    player: _player,
    osdEnabled: () => _settings.osdEnabled,
    isMounted: () => mounted,
    update: setState,
    osdMessageProbe: widget.osdMessageProbe,
  );
  late final MediaSessionCoordinator _media;
  late final TrackChapterController _tracks = TrackChapterController(
    settings: _settings,
    playerService: _playerService,
    audioSession: _audioSession,
    player: _player,
    playback: _playback,
    pickers: _pickers,
    log: _log,
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    update: setState,
    l10n: () => AppLocalizations.of(context),
    showOsd: _showOsdMessage,
    showMessage: (message) => showAppSnackBar(context, message),
    syncIdleInhibit: _media.syncIdleInhibit,
    captureBookmark: (path) => _sourceLoad.captureBookmarkFor(path),
    reloadSourceForMixChange: (source) => _sourceLoad.loadSource(
      source,
      syncPlaylist: false,
      applyResume: false,
      origin: SourceOrigin.queue,
    ),
  );
  late final PlayerMediaInfoPresenter _mediaInfo = PlayerMediaInfoPresenter(
    player: _player,
    playerService: _playerService,
    media: _media,
    trackController: _tracks,
  );
  late final PlayerTransportController _transport = PlayerTransportController(
    settings: _settings,
    playerService: _playerService,
    player: _player,
    playlist: () => _playlist,
    media: _media,
    window: _window,
    log: _log,
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    update: setState,
    l10n: () => AppLocalizations.of(context),
    showOsd: _showOsdMessage,
  );
  late final PlayerSettingsApplier _settingsApplier = PlayerSettingsApplier(
    settings: _settings,
    advancedPlayback: _advancedPlayback,
    playerService: _playerService,
    player: _player,
    tracks: _tracks,
    media: _media,
    seekPreview: _seekPreviewService,
    window: _window,
    transport: _transport,
    log: _log,
    hasCurrentFile: () => _currentFile != null,
    isMounted: () => mounted,
    update: setState,
  );
  late final PlayerOpenActions _open = PlayerOpenActions(
    settings: _settings,
    pickers: _pickers,
    sourceLoad: _sourceLoad,
    playlist: () => _playlist,
    hasCurrentFile: () => _currentFile != null,
    log: _log,
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    l10n: () => AppLocalizations.of(context),
    showMessage: (message) => showAppSnackBar(context, message),
    promptForUrl: () => _pickers.promptForUrl(context),
    confirmClearQueue: () => showClearQueueConfirmation(context),
  );
  late final PlayerMenuBridge _menuBridge = PlayerMenuBridge(
    settings: _settings,
    media: _media,
    open: _open,
    isActive: () => mounted && !_isDisposed,
    onCheckForUpdates: () => _updateNotice.runManualCheck(context),
    onOpenPreferences: _openSettings,
  );
  late final PlayerScreenshotAction _screenshot = PlayerScreenshotAction(
    settings: _settings,
    playerService: _playerService,
    player: _player,
    sourceLoad: _sourceLoad,
    log: _log,
    isMounted: () => mounted,
    l10n: () => AppLocalizations.of(context),
    showOsd: _showOsdMessage,
    showMessage: (message) => showAppSnackBar(context, message),
    operationForTesting: () => widget.screenshotOperationForTesting,
  );
  late final PlayerShortcutActions _shortcutActions = PlayerShortcutActions(
    settings: _settings,
    advancedPlayback: _advancedPlayback,
    playerService: _playerService,
    window: _window,
    transport: _transport,
    tracks: _tracks,
    sourceLoad: _sourceLoad,
    open: _open,
    screenshot: _screenshot,
    log: _log,
    hasCurrentFile: () => _currentFile != null,
    pulseOsd: _pulseOsd,
    handleEscape: _handleEscapeBack,
    toggleQueueDrawer: _toggleQueueDrawer,
    openSettings: _openSettings,
    showMediaInfo: () => unawaited(_mediaInfo.show(context)),
  );
  late final PlayerMoreMenuController _moreMenu = PlayerMoreMenuController(
    settings: _settings,
    player: _player,
    advancedPlayback: _advancedPlayback,
    sleepTimer: _sleepTimer,
    playlist: () => _playlist,
    window: _window,
    transport: _transport,
    trackController: _tracks,
    sourceLoad: _sourceLoad,
    open: _open,
    screenshot: _screenshot,
    hasCurrentFile: () => _currentFile != null,
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    l10n: () => AppLocalizations.of(context),
    showTimedMessage: (message) =>
        showAppSnackBar(context, message, duration: _snackbarShortDuration),
    openQueueDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
  );
  late final PlayerUpdateNotice _updateNotice = PlayerUpdateNotice(
    settings: _settings,
    updateService: _updateService,
    debugLog: widget.debugLog,
    log: _log,
  );
  late final PlaylistService _playlist;
  late final OpenFileBridge _openFileBridge;

  late final PlayerWindowController _window = PlayerWindowController(
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    alwaysOnTop: () => _settings.alwaysOnTop,
    log: _log,
    onFullscreenRejected: () => showAppSnackBar(
      context,
      AppLocalizations.of(context).snackFullscreenRejected,
      duration: _snackbarShortDuration,
    ),
    onCompactModeChanged: _onCompactModeChanged,
    shouldHoldChrome: () =>
        !_player.isPlaying || _endDrawerOpen || !_playerRouteIsCurrent(),
    videoAspectRatio: _currentVideoAspectRatio,
  );

  bool _endDrawerOpen = false;

  // Resume-position bookkeeping.
  Timer? _resumeSaveTimer;
  Timer? _updateCheckTimer;

  late final SourceLoadCoordinator _sourceLoad = SourceLoadCoordinator(
    settings: _settings,
    playerService: _playerService,
    playback: _playback,
    player: _player,
    playlist: _playlist,
    media: _media,
    tracks: _tracks,
    pickers: _pickers,
    advancedPlayback: _advancedPlayback,
    seekPreview: _seekPreviewService,
    log: _log,
    isMounted: () => mounted,
    isDisposed: () => _isDisposed,
    isHeadlessMedia: () => _headlessMedia,
    update: setState,
    l10n: () => AppLocalizations.of(context),
    showOsd: _showOsdMessage,
    showMessage: (message) => showAppSnackBar(context, message),
  );

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
    _sleepTimer = SleepTimerController(
      onFire: () => _moreMenu.onSleepTimerFired(),
    );
    unawaited(_seekPreviewService.setEnabled(_settings.seekPreviewEnabled));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      unawaited(() async {
        await _settings.pruneRecentFiles(notifyListeners: false);
        if (_isDisposed) return;
        await _media.syncJumpList();
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
    _media = MediaSessionCoordinator(
      settings: _settings,
      playerService: _playerService,
      mediaSession: MediaSessionService(debugLog: widget.debugLog),
      idleInhibit: IdleInhibitService(),
      player: _player,
      playback: _playback,
      log: _log,
      isMounted: () => mounted,
      isDisposed: () => _isDisposed,
      update: setState,
      onStop: () => _sourceLoad.stopPlaybackAndResetUi(),
      onAdvancePlaylist: (delta) => _sourceLoad.advancePlaylist(delta),
      onSetShuffle: (on) => _transport.setShuffle(on),
      onQuitRequest: () => widget.onQuitRequest,
    );
    _media.init();
    _playlist = PlaylistService()..setShuffle(_settings.playlistShuffle);
    _player.volume = _settings.volume;
    _settingsApplier.captureInitialState();
    _log(
      'player_init',
      detailsBuilder: () => {
        'auto_play': _settings.autoPlay,
        'volume': _player.volume.toStringAsFixed(2),
        'speed': _settings.speed.toStringAsFixed(2),
        'loop_mode': _settings.loopMode.name,
      },
    );

    _window.addListener(_onWindowChanged);
    windowManager.addListener(this);
    _shortcuts.attach();

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
    _transport.applySpeed(_settings.speed);
    _transport.applyLoopMode(_settings.loopMode);
    _transport.applyHwDec(_settings.hwDec);

    final streamSubs = <StreamSubscription>[
      _playerService.positionStream.listen((pos) {
        if (!mounted || _isDisposed) return;
        _advancedPlayback.setPosition(pos);
        final update = _player.onPosition(pos);
        if (update == PositionUiUpdate.skip) return;
        if (update == PositionUiUpdate.notify) {
          setState(() {});
        }
        _media.onPosition(pos);
      }),
      _playerService.durationStream.listen((dur) {
        if (!mounted || _isDisposed) return;
        unawaited(_window.syncCompactAspectRatio());
        final packagedProbe = _packagedE2eProbe;
        if (packagedProbe != null) {
          unawaited(packagedProbe.recordDuration(dur));
        }
        _advancedPlayback.setDuration(dur);
        setState(() => _player.duration = dur);
        _media.onDuration(dur);
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
        if (playing) {
          _window.onChromeHoldsChanged();
        } else {
          _window.revealFullscreenChrome();
        }
        // Save on pause: the periodic saver only runs while playing, so a
        // pause (and any seek after it) would otherwise not be stored.
        if (!playing && !_player.fileOpenInProgress) {
          _sourceLoad.persistResumePosition();
        }
        _media.onPlayingChanged(playing);
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
        _media.updateVolume(vol);
        if (widget.debugLog.isEnabled) {
          _log(
            'volume_stream_updated',
            detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
          );
        }
      }),
      _playerService.videoWidthStream.listen((w) {
        if (!mounted || _isDisposed) return;
        final videoOutputChanged = _player.onVideoWidth(w);
        unawaited(_window.syncCompactAspectRatio());
        if (videoOutputChanged) {
          setState(() {});
          _media.syncIdleInhibit();
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
        unawaited(_window.syncCompactAspectRatio());
        if (_sourceLoad.stopInProgress || _player.fileOpenInProgress) return;
        _tracks.cacheTracksForCurrentLoad(
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
        if (_sourceLoad.stopInProgress || _playback.loadQueue.isBusy) return;
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
          unawaited(_sourceLoad.advancePlaylist(1));
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
    _media.attachCommands(
      _subscriptions,
      testCommands: widget.mediaSessionCommandsForTesting?.stream,
    );

    // Periodic resume-position saver (every 5s while playing).
    _resumeSaveTimer = Timer.periodic(
      _resumeSaveInterval,
      (_) => _sourceLoad.persistResumePosition(requirePlaying: true),
    );

    _updateNotice.checkForUpdates(context);
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (!_isDisposed && mounted) _updateNotice.checkForUpdates(context);
    });

    _openFileBridge = OpenFileBridge(
      onOpenRequest: _sourceLoad.openRequestedFileRequest,
      onOpenBatch: _sourceLoad.openRequestedFileBatch,
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
    _settings.addListener(_settingsApplier.onSettingsChanged);
    _initializePlatformFileOpenBridge();
    _menuBridge.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_updateNotice.showPendingNotice(context));
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
        _sourceLoad.applyDroppedPaths(
          seededDropPaths,
          origin: SourceOrigin.dragDrop,
        );
      });
    }

    final pendingLoad = widget.initialPendingLoad;
    if (pendingLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        unawaited(_sourceLoad.loadSource(pendingLoad));
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
                unawaited(_media.refreshMetadata(source));
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
    _sourceLoad.persistResumePosition();
    await _settings.flushResumePositions();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_window.compactMode) {
      widget.onCompactModeChanged?.call(false);
    }
    AppExitHooks.remove(_saveStateBeforeExit);
    _shortcuts.dispose();
    windowManager.removeListener(this);
    _menuBridge.dispose();
    _messenger.dispose();
    _window.dispose();
    _resumeSaveTimer?.cancel();
    _updateCheckTimer?.cancel();
    _sourceLoad.persistResumePosition();
    _log('player_dispose');
    _settings.removeListener(_settingsApplier.onSettingsChanged);
    _openFileBridge.dispose();
    _subscriptions.cancelAll();
    _sleepTimer.dispose();
    _advancedPlayback.dispose();
    _playback.dispose();
    _player.dispose();
    _sourceLoad.releaseActiveBookmark();
    _media.dispose();
    _playlist.dispose();
    unawaited(_seekPreviewService.dispose());
    unawaited(_playerService.dispose());
    super.dispose();
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

  bool _shouldEnableHardwareAcceleration(String hwDec) {
    return HardwareAccelerationService.shouldEnableHardwareAcceleration(hwDec);
  }

  void _openSettings() {
    if (!_playerRouteIsCurrent()) return;
    openPlayerSettings(
      context: context,
      settings: _settings,
      debugLog: widget.debugLog,
      updateService: _updateService,
      log: _log,
    );
  }

  void _toggleQueueDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    if (scaffold.isEndDrawerOpen) {
      scaffold.closeEndDrawer();
    } else {
      scaffold.openEndDrawer();
    }
  }

  // ── File handling ─────────────────────────────────────────

  void _onDragDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    _sourceLoad.applyDroppedPaths(
      details.files.map((file) => file.path),
      origin: SourceOrigin.dragDrop,
    );
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

  // ── Keyboard shortcuts ────────────────────────────────────

  bool _playerRouteIsCurrent() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  void _onEndDrawerChanged(bool isOpen) {
    _endDrawerOpen = isOpen;
    _window.onChromeHoldsChanged();
  }

  @override
  void onWindowFocus() {
    _shortcuts.restoreFocus(refocusNativeWindow: false);
  }

  @override
  void onWindowEnterFullScreen() => _window.onEnterFullScreen();

  @override
  void onWindowLeaveFullScreen() => _window.onLeaveFullScreen();

  void _onWindowChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onCompactModeChanged(bool compact) {
    widget.onCompactModeChanged?.call(compact);
    final l10n = AppLocalizations.of(context);
    _showOsdMessage(compact ? l10n.osdMiniPlayerOn : l10n.osdMiniPlayerOff);
  }

  /// Escape: close queue drawer → exit fullscreen → otherwise ignore.
  KeyEventResult _handleEscapeBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isEndDrawerOpen ?? false) {
      _log('shortcut_close_queue_drawer', category: DebugLogCategory.ui);
      scaffold!.closeEndDrawer();
      return KeyEventResult.handled;
    }
    if (_window.isFullscreen) {
      _log('shortcut_exit_fullscreen', category: DebugLogCategory.ui);
      unawaited(_window.exitFullscreen());
      return KeyEventResult.handled;
    }
    // Cache can drift if fullscreen was entered outside our toggle path;
    // reconcile asynchronously without swallowing Escape when windowed.
    unawaited(_window.exitFullscreenIfActuallyFullscreen());
    return KeyEventResult.ignored;
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shortcuts.focusNode,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _shortcuts.handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        endDrawer: _buildPlayQueueDrawer(),
        onEndDrawerChanged: _onEndDrawerChanged,
        body: GlassShellBackground(
          child: _window.isFullscreen
              ? _buildFullscreenBody()
              : (_window.compactMode
                    ? _buildCompactBody()
                    : _buildWindowedBody()),
        ),
      ),
    );
  }

  Widget _buildDropTarget({required Widget child}) {
    return DropTarget(
      onDragEntered: (_) => _onDragEntered(),
      onDragExited: (_) => _onDragExited(),
      onDragDone: _onDragDone,
      child: child,
    );
  }

  Widget _buildMediaStack() {
    return Stack(
      key: _mediaStackKey,
      fit: StackFit.expand,
      children: [
        _buildMediaSurface(),
        PlayerDragOverlay(visible: _isDragging),
        Positioned(
          left: 0,
          top: 0,
          width: 0,
          height: 0,
          child: _RouteCurrentProbe(onChanged: _window.onChromeHoldsChanged),
        ),
      ],
    );
  }

  Widget _buildWindowedBody() {
    return Column(
      children: [
        const CustomTitleBar(),
        Expanded(
          child: _buildDropTarget(
            child: Column(
              children: [
                Expanded(child: _buildMediaStack()),
                _buildBottomDock(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBody() {
    return _buildDropTarget(
      child: ListenableBuilder(
        listenable: Listenable.merge([_playlist, _settings]),
        builder: (context, _) {
          return MiniPlayerLayout(
            key: const ValueKey('mini-player-layout'),
            surface: _buildMediaStack(),
            title: _miniPlayerTitle(),
            artist: _player.isAudioFile ? _media.displayArtist : null,
            hasMedia: _currentFile != null,
            isPlaying: _player.isPlaying,
            position: _player.position,
            duration: _player.duration,
            canGoPrevious: PlaylistAdvancePolicy.canGoPrevious(
              queueLength: _playlist.length,
              loopMode: _settings.loopMode,
              hasPreviousInOrder: _playlist.hasPrevious,
            ),
            canGoNext: PlaylistAdvancePolicy.canGoNext(
              queueLength: _playlist.length,
              loopMode: _settings.loopMode,
              hasNextInOrder: _playlist.hasNext,
            ),
            onExit: () => unawaited(_window.toggleCompactMode()),
            onPlayPause: _onControlPlayPause,
            onPrevious: () => unawaited(_sourceLoad.advancePlaylist(-1)),
            onNext: () => unawaited(_sourceLoad.advancePlaylist(1)),
            onSeekStart: _onSeekStart,
            onSeekChange: _onSeekChange,
            onSeekEnd: _onSeekEnd,
            onDragWindow: _window.startWindowDrag,
          );
        },
      ),
    );
  }

  String _miniPlayerTitle() {
    final shown = _media.displayTitle;
    if (shown != null && shown.isNotEmpty) return shown;
    return _player.osdTitle();
  }

  Future<double?> _currentVideoAspectRatio() async {
    if (_player.isAudioFile || !_player.hasVideoOutput) return null;
    final width = double.tryParse(
      await _playerService.getProperty('dwidth') ?? '',
    );
    final height = double.tryParse(
      await _playerService.getProperty('dheight') ?? '',
    );
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  void _onSeekStart() => _player.isSeeking = true;

  void _onSeekChange(double value) {
    setState(() {
      _player.position = Duration(milliseconds: value.toInt());
    });
  }

  void _onSeekEnd(double value) {
    _player.isSeeking = false;
    unawaited(
      _playerService.seek(Duration(milliseconds: value.toInt())).catchError((
        Object e,
      ) {
        _log(
          'seek_slider_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
  }

  Future<void> _onControlPlayPause() async {
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
  }

  Widget _buildFullscreenBody() {
    final chromeVisible = _window.fullscreenChromeVisible;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => _window.revealFullscreenChrome(),
      onPointerMove: (_) => _window.revealFullscreenChrome(),
      onPointerDown: (_) => _window.revealFullscreenChrome(),
      child: _buildDropTarget(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildMediaStack()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FullscreenChromeOverlay(
                key: const ValueKey('fullscreen-title-overlay'),
                edge: FullscreenChromeEdge.top,
                visible: chromeVisible,
                onPointerOverChanged: _window.setPointerOverChrome,
                onPointerDown: _window.pointerDownInChrome,
                onPointerUp: _window.pointerUpInChrome,
                child: const CustomTitleBar(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FullscreenChromeOverlay(
                key: const ValueKey('fullscreen-dock-overlay'),
                edge: FullscreenChromeEdge.bottom,
                visible: chromeVisible,
                onPointerOverChanged: _window.setPointerOverChrome,
                onPointerDown: _window.pointerDownInChrome,
                onPointerUp: _window.pointerUpInChrome,
                child: _buildBottomDock(),
              ),
            ),
          ],
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
      playlist: _playlist,
      onSeekStart: _onSeekStart,
      onSeekChange: _onSeekChange,
      onSeekEnd: _onSeekEnd,
      onPlayPause: _onControlPlayPause,
      onStop: () async {
        _log('control_stop_pressed', category: DebugLogCategory.ui);
        await _sourceLoad.stopPlaybackAndResetUi();
      },
      onOpenFile: _open.openFile,
      onOpenFolder: () => unawaited(_open.openFolder()),
      onOpenUrl: () => unawaited(_open.openUrl()),
      onReopenLast: () {
        _log('control_reopen_last_pressed', category: DebugLogCategory.ui);
        unawaited(_open.reopenLastFile());
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
      onRecentFileSelected: _open.loadRecentFile,
      onSettingsPressed: _openSettings,
      onMoreActions: (anchor) =>
          unawaited(_moreMenu.showMoreMenu(context, anchor: anchor)),
      onPrevious: () => unawaited(_sourceLoad.advancePlaylist(-1)),
      onNext: () => unawaited(_sourceLoad.advancePlaylist(1)),
      onToggleQueue: () => _scaffoldKey.currentState?.openEndDrawer(),
      onToggleMute: _transport.toggleMute,
      onCycleSpeed: _transport.cyclePlaybackSpeed,
    );
  }

  Widget _buildPlayQueueDrawer() {
    return PlayQueueDrawer(
      playlist: _playlist,
      hasCurrentFile: () => _currentFile != null,
      onShowMediaInfo: () => unawaited(_mediaInfo.show(context)),
      onSetShuffle: _transport.setShuffle,
      onClearQueue: () => unawaited(_open.clearQueueWithConfirmation()),
      onActivateItem: (source) => unawaited(
        _sourceLoad.loadSource(
          source,
          syncPlaylist: false,
          origin: SourceOrigin.queue,
        ),
      ),
      onRemoveItem: (index) => unawaited(_open.removeQueueItem(index)),
      onAddFiles: _open.pickFilesToEnqueue,
      onAddFolder: (playNow) => unawaited(_open.openFolder(playNow: playNow)),
      onOpenPlaylist: (playNow) =>
          unawaited(_open.openPlaylistPicker(playNow: playNow)),
      onSavePlaylist: () => unawaited(_open.exportPlaylistQueue()),
      onRemoveMissing: () => unawaited(_open.removeMissingQueueItems()),
    );
  }

  Widget _buildMediaSurface() {
    return MediaSurface(
      player: _player,
      settings: _settings,
      hasMedia: _currentFile != null,
      videoController: _videoController,
      mediaDisplayTitle: _media.displayTitle,
      mediaDisplayArtist: _media.displayArtist,
      mediaDisplayAlbum: _media.displayAlbum,
      recentFiles: _settings.recentFiles,
      onOpenRecent: _open.loadRecentFile,
      compactMode: _window.compactMode,
      isFullscreen: _window.isFullscreen,
      fullscreenChromeVisible: _window.fullscreenChromeVisible,
      onTap: () {
        _shortcuts.restoreFocus(refocusNativeWindow: false);
        _window.revealFullscreenChrome();
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
        if (_window.compactMode) {
          unawaited(_window.toggleCompactMode());
          return;
        }
        unawaited(_window.toggleFullscreen());
      },
      onHover: () {
        _pulseOsd();
        _window.revealFullscreenChrome();
      },
      onScrollVolume: (scrollDeltaY, timeStamp) {
        if (_currentFile == null) return;
        _window.revealFullscreenChrome();
        final step = _scrollVolume.add(scrollDeltaY, timeStamp);
        if (step != 0) _transport.adjustVolume(step);
      },
      onDismissEmptyStateTip: () => setState(() {
        _settings.emptyStateTipDismissed = true;
      }),
      onOpenFile: _open.openFile,
      onOpenFolder: () => unawaited(_open.openFolder()),
      onOpenPlaylist: () => unawaited(_open.openPlaylistPicker()),
      onOpenUrl: () => unawaited(_open.openUrl()),
      onReopenLast: _open.reopenLastFile,
    );
  }

  // ── OSD ────────────────────────────────────────────────────

  void _pulseOsd() => _messenger.pulseOsd();

  void _showOsdMessage(String msg) => _messenger.showOsdMessage(msg);
}

class _RouteCurrentProbe extends StatefulWidget {
  const _RouteCurrentProbe({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_RouteCurrentProbe> createState() => _RouteCurrentProbeState();
}

class _RouteCurrentProbeState extends State<_RouteCurrentProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
