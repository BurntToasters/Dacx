import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../services/player_service.dart';
import '../services/player_shortcuts_service.dart';
import '../services/instance_mode_service.dart';
import '../services/settings_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/debug_log_service.dart';
import '../services/equalizer_service.dart';
import '../services/media_session_service.dart';
import '../services/playlist_service.dart';
import '../services/bookmark_service.dart';
import '../services/open_file_bridge.dart';
import '../services/seek_preview_service.dart';
import '../services/audio_spectrum_service.dart';
import '../services/self_update_service.dart';
import '../models/chapter_info.dart';
import '../models/playable_source.dart';
import '../l10n/app_localizations.dart';
import '../theme/glass_decorations.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../playback/audio_filter_chain.dart';
import '../playback/chapter_list_loader.dart';
import '../playback/media_folder_scanner.dart';
import '../playback/playback_controller.dart';
import '../playback/playback_mix_policy.dart';
import '../playback/media_session_command_dispatch.dart';
import '../playback/player_path_utils.dart';
import '../playback/player_controller.dart';
import '../playback/player_settings_sync.dart';
import '../playback/player_ui_policies.dart';
import '../playback/chapter_navigation_policy.dart';
import '../playback/enqueue_policy.dart';
import '../playback/resume_playback_policy.dart';
import '../playback/source_load_post_open_policy.dart';
import '../playback/osd_policy.dart';
import '../playback/track_cycle_policy.dart';
import '../playback/source_load_validation_policy.dart';
import '../playback/source_open_policy.dart';
import '../playback/volume_policy.dart';
import '../playback/track_label.dart';
import '../playback/update_launch_policy.dart';
import '../playback/subscription_bag.dart';
import '../widgets/compact_exit_button.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/media_info_dialog.dart';
import '../widgets/open_url_dialog.dart';
import '../widgets/osd_overlay.dart';
import '../widgets/queue_item_tile.dart';
import '../widgets/update_progress_dialog.dart';
import '../widgets/seek_slider.dart';
import '../widgets/audio_spectrum_visualizer.dart';
import '../widgets/transport_controls.dart';
import 'settings_screen.dart';

const _resumeSaveInterval = Duration(seconds: 5);
const _seekStep = Duration(seconds: 5);
const _seekStepBack = Duration(seconds: -5);
const _osdHideDuration = Duration(seconds: 3);
const _updateSnackbarDuration = Duration(seconds: 10);
const _snackbarShortDuration = Duration(seconds: 2);
const _resumeStartThreshold = Duration(seconds: 1);
const _settingsFwdTransition = Duration(milliseconds: 340);
const _settingsRevTransition = Duration(milliseconds: 280);
const _sheetTransitionDuration = Duration(milliseconds: 180);
const _contentSwitchDuration = Duration(milliseconds: 240);
const _animFastDuration = Duration(milliseconds: 140);
const _seekBarSizeDuration = Duration(milliseconds: 190);
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
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final IPlayerService _playerService;
  VideoController? _videoController;
  late final SeekPreviewService _seekPreviewService;
  late final AudioSpectrumService _audioSpectrum;
  late final PlaybackController _playback;
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

  // Tracks / chapters / OSD state
  Timer? _osdHideTimer;
  late final MediaSessionService _mediaSession;
  late final PlaylistService _playlist;
  late final OpenFileBridge _openFileBridge;

  // Compact mini-player mode (PiP-style on desktop).
  bool _compactMode = false;
  Size? _preCompactSize;
  Offset? _preCompactPos;
  bool _preCompactAlwaysOnTop = false;
  static const Size _compactWindowSize = Size(480, 320);

  // Resume-position bookkeeping.
  Timer? _resumeSaveTimer;

  String? _activeBookmarkToken;

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
    _seekPreviewService = SeekPreviewService();
    _audioSpectrum = AudioSpectrumService(playerService: _playerService);
    unawaited(_seekPreviewService.setEnabled(_settings.seekPreviewEnabled));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      _settings.pruneRecentFiles(notifyListeners: false);
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
      lastMultiAudioMix: _settings.multiAudioMix,
      lastAudioWaveformEnabled: _settings.audioWaveformEnabled,
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
        final update = _player.onPosition(pos);
        if (update == PositionUiUpdate.skip) return;
        if (update == PositionUiUpdate.notify) {
          setState(() {});
        }
        if (_settings.mediaSessionEnabled) {
          _maybeUpdateMediaSessionPosition(pos);
        }
      }),
      _playerService.durationStream.listen((dur) {
        if (!mounted || _isDisposed) return;
        setState(() => _player.duration = dur);
        if (dur.inMilliseconds > 0 && _settings.mediaSessionEnabled) {
          final source = _player.currentSource;
          if (source != null) {
            unawaited(
              _mediaSession.updateMetadata(
                title: source.displayName,
                duration: dur,
              ),
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
        setState(() => _player.isPlaying = playing);
        _syncSpectrumService(playing);
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

        final albumArtTrack = PlayerController.firstEmbeddedAlbumArtTrack(
          tracks,
        );
        if (albumArtTrack != null) {
          unawaited(
            _playerService.setVideoTrack(albumArtTrack).catchError((Object e) {
              _log(
                'album_art_track_select_failed',
                message: e.toString(),
                severity: DebugSeverity.warn,
              );
            }),
          );
        }
      }),
      _playerService.errorStream.listen((event) {
        if (!mounted || _isDisposed) return;
        _log(
          'player_operation_failed',
          message: event.toString(),
          severity: DebugSeverity.warn,
        );
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          final l10n = AppLocalizations.of(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.snackPlaybackOperationFailed(event.error.toString()),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }),
      _playerService.tracksStream.listen((tracks) {
        if (!mounted || _isDisposed) return;
        if (_player.fileOpenInProgress) return;
        _cacheTracksForCurrentLoad(tracks, refreshChapters: true);
      }),
      _playerService.completedStream.listen((completed) {
        if (!mounted || _isDisposed || !completed) return;
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
        if (_settings.loopMode != LoopMode.single) {
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
    _subscriptions.add(_mediaSession.commands.listen(_onMediaSessionCommand));

    // Periodic resume-position saver (every 5s while playing).
    _resumeSaveTimer = Timer.periodic(
      _resumeSaveInterval,
      (_) => _persistResumePosition(),
    );

    _openFileBridge = OpenFileBridge(
      onOpenRequest: _openRequestedFileRequest,
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

    // Listen for settings changes (speed, loop, always-on-top).
    _settings.addListener(_onSettingsChanged);
    _initializePlatformFileOpenBridge();

    _checkForUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showPendingUpdateNotice());
    });

    // Auto-open CLI file.
    if (widget.initialFile != null) {
      _log(
        'initial_file_requested',
        detailsBuilder: () => {'path': widget.initialFile},
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openRequestedFile(widget.initialFile!, forcePlay: true));
      });
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
  }

  @override
  void dispose() {
    _isDisposed = true;
    _osdHideTimer?.cancel();
    _resumeSaveTimer?.cancel();
    _persistResumePosition();
    _log('player_dispose');
    _settings.removeListener(_onSettingsChanged);
    _openFileBridge.dispose();
    _subscriptions.cancelAll();
    _playback.dispose();
    _player.dispose();
    _releaseActiveBookmark();
    unawaited(_mediaSession.dispose());
    _playlist.dispose();
    unawaited(_seekPreviewService.dispose());
    _audioSpectrum.dispose();
    unawaited(_playerService.dispose());
    super.dispose();
  }

  void _releaseActiveBookmark() {
    final token = _activeBookmarkToken;
    if (token == null || token.isEmpty) return;
    _activeBookmarkToken = null;
    unawaited(BookmarkService.stop(token));
  }

  Future<String> _resolveSandboxedPath(String requestedPath) async {
    if (!BookmarkService.isSupported) return requestedPath;
    final bookmark = _settings.fileBookmark(requestedPath);
    if (bookmark == null || bookmark.isEmpty) return requestedPath;
    final resolved = await BookmarkService.resolveAndStart(bookmark);
    if (resolved == null) {
      _settings.removeFileBookmark(requestedPath);
      return requestedPath;
    }
    _releaseActiveBookmark();
    _activeBookmarkToken = resolved.token.isNotEmpty ? resolved.token : null;
    final bookmarkToPersist = resolved.refreshed ?? bookmark;
    if (resolved.path != requestedPath) {
      _settings.setFileBookmark(resolved.path, bookmarkToPersist);
    } else if (resolved.stale && resolved.refreshed != null) {
      _settings.setFileBookmark(requestedPath, resolved.refreshed!);
    }
    return resolved.path;
  }

  Future<void> _captureBookmarkFor(String path) async {
    if (!BookmarkService.isSupported) return;
    final bookmark = await BookmarkService.createBookmark(path);
    if (bookmark != null && bookmark.isNotEmpty) {
      _settings.setFileBookmark(path, bookmark);
    }
  }

  void _onSettingsChanged() {
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

    if (delta.audioFilters) {
      _syncSpectrumService(_player.isPlaying);
    }

    if (delta.multiAudioMix) {
      unawaited(_applyMultiAudioMix());
    }

    if (delta.mediaSessionEnabled != null) {
      unawaited(_mediaSession.setEnabled(delta.mediaSessionEnabled!));
    }

    if (delta.playlistShuffle != null) {
      unawaited(_mediaSession.updateShuffle(delta.playlistShuffle!));
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
    unawaited(_openFileBridge.bootstrap(subscriptions: _subscriptions));
  }

  Future<void> _openRequestedFile(
    String filePath, {
    bool forcePlay = false,
  }) async {
    await _openRequestedFileRequest(
      OpenFileRequest(path: filePath),
      forcePlay: forcePlay,
    );
  }

  Future<void> _openRequestedFileRequest(
    OpenFileRequest request, {
    bool forcePlay = false,
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
        'open_requested_same_file_ignored',
        detailsBuilder: () => {'path': trimmed},
      );
      if (SourceOpenPolicy.shouldForcePlaySameFile(
        forcePlay: forcePlay,
        isPlaying: _player.isPlaying,
      )) {
        unawaited(_playerService.playPause().catchError((_) {}));
      }
      return;
    }
    _log(
      'open_requested',
      detailsBuilder: () => {'path': trimmed, 'force_play': forcePlay},
    );
    await _loadFile(trimmed, forcePlay: forcePlay);
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
  }

  double _dialogWidth(BuildContext context, double desired) {
    final available = MediaQuery.sizeOf(context).width - 48;
    return math.min(desired, math.max(280.0, available));
  }

  double _dialogHeight(BuildContext context, double desired) {
    final available = MediaQuery.sizeOf(context).height - 120;
    return math.min(desired, math.max(160.0, available));
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).snackUpdatedToVersion(targetVersion),
          ),
        ),
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).snackUpdateMayHaveFailed(targetVersion),
          ),
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).snackUpdateAvailable(update.version),
        ),
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
      ),
    );
  }

  // ── File handling ─────────────────────────────────────────

  Future<void> _openFile() async {
    _log('file_picker_open_requested');
    try {
      final initialDirectory = _settings.lastOpenDirectory;
      final file = await FilePicker.pickFile(
        type: FileType.any,
        lockParentWindow: true,
        initialDirectory: initialDirectory,
      );

      if (file == null) {
        _log('file_picker_cancelled');
        return;
      }
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        _log('file_picker_invalid_path', severity: DebugSeverity.warn);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).snackCouldNotReadSelectedFile,
              ),
            ),
          );
        }
        return;
      }

      await _captureBookmarkFor(path.trim());
      await _loadFile(path);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).snackFilePickerFailed(detail),
            ),
          ),
        );
      }
    } catch (e) {
      _log(
        'file_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).snackUnableToOpenFilePicker,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openFolder({bool playNow = true}) async {
    _log('folder_picker_open_requested');
    try {
      final folder = await FilePicker.getDirectoryPath(
        lockParentWindow: true,
        initialDirectory: _settings.lastOpenDirectory,
      );
      if (folder == null || folder.trim().isEmpty) {
        _log('folder_picker_cancelled');
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _settings.lastOpenDirectory = folder.trim();
      final scan = await MediaFolderScanner.scan(
        folder,
        maxItems: PlaylistService.maxQueueItems,
      );
      if (!mounted) return;
      if (scan.paths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.snackNoSupportedMediaInFolder)),
          );
        }
        return;
      }
      _enqueue(scan.paths, playNow: playNow);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(parts.join(' '))));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).snackFolderScanFailed(detail),
            ),
          ),
        );
      }
    } catch (e) {
      _log(
        'folder_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).snackFolderScanFailed(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openUrl() async {
    if (!PlayerUiPolicies.showOpenUrlButton(_settings)) return;
    final l10n = AppLocalizations.of(context);
    final url = await OpenUrlDialog.show(context);
    if (!mounted) return;
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (!PlayableSource.isSupportedUrl(trimmed)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackInvalidStreamUrl)));
      }
      return;
    }
    await _loadSource(PlayableSource.url(trimmed));
  }

  Future<void> _loadFile(String filePath, {bool forcePlay = false}) {
    return _loadSource(PlayableSource.file(filePath), forcePlay: forcePlay);
  }

  Future<void> _loadSource(PlayableSource source, {bool forcePlay = false}) {
    return _playback.loadQueue.enqueue(
      () => _loadSourceInternal(source, forcePlay: forcePlay),
      onError: (Object e, StackTrace st) {
        _log(
          'load_queue_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      },
    );
  }

  void _maybeUpdateMediaSessionPosition(Duration pos) {
    if (!_playback.mediaSessionThrottle.shouldSend(DateTime.now())) {
      return;
    }
    unawaited(_mediaSession.updatePosition(pos, playing: _player.isPlaying));
  }

  Future<void> _refreshChaptersIfNeeded() async {
    final countRaw = await _playerService.getProperty('chapter-list/count');
    final count = int.tryParse(countRaw ?? '') ?? 0;
    if (!_playback.chapterGate.shouldRefresh(
      path: _currentFile,
      chapterCount: count,
    )) {
      return;
    }
    await _refreshChapters(expectedCount: count);
  }

  Future<void> _loadSourceInternal(
    PlayableSource source, {
    bool forcePlay = false,
  }) async {
    if (_isDisposed) return;
    final requestedValue = source.value.trim();
    final validation = SourceLoadValidationPolicy.validateRequest(
      source: source,
      trimmedValue: requestedValue,
    );
    switch (validation.failure) {
      case SourceLoadValidationFailure.emptySource:
        _log(
          'media_load_invalid_source',
          detailsBuilder: () => {'source': source.value},
          severity: DebugSeverity.warn,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).snackInvalidFilePath),
            ),
          );
        }
        return;
      case SourceLoadValidationFailure.invalidUrl:
        _log(
          'url_load_invalid',
          detailsBuilder: () => {'url': requestedValue},
          severity: DebugSeverity.warn,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).snackInvalidStreamUrl),
            ),
          );
        }
        return;
      case SourceLoadValidationFailure.missingFile:
        _log(
          'file_load_missing',
          detailsBuilder: () => {'path': requestedValue},
          severity: DebugSeverity.warn,
        );
        _settings.pruneRecentFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).snackFileNotFound),
            ),
          );
        }
        return;
      case SourceLoadValidationFailure.none:
        break;
    }

    final normalizedSource = source.isUrl
        ? PlayableSource.url(requestedValue)
        : PlayableSource.file(await _resolveSandboxedPath(requestedValue));
    final normalizedValue = normalizedSource.value;

    final fileValidation = SourceLoadValidationPolicy.validateNormalizedFile(
      isFile: normalizedSource.isFile,
      fileExists: _headlessMedia || File(normalizedValue).existsSync(),
    );
    if (fileValidation.failure == SourceLoadValidationFailure.missingFile) {
      _log(
        'file_load_missing',
        detailsBuilder: () => {'path': normalizedValue},
        severity: DebugSeverity.warn,
      );
      _settings.pruneRecentFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).snackFileNotFound),
          ),
        );
      }
      return;
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
    if (normalizedSource.isFile && !PlayerPathUtils.isSupportedExtension(ext)) {
      _log(
        'file_load_unrecognized_extension',
        detailsBuilder: () => {'extension': ext, 'path': normalizedValue},
        severity: DebugSeverity.warn,
      );
    }
    final gen = _playback.beginLoad();
    if (!mounted || _isDisposed) return;
    _persistResumePosition();
    _playback.chapterGate.invalidate();
    setState(() {
      _player.beginSourceLoad(normalizedSource, ext);
    });
    _audioSpectrum.resetDynamics();
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
      await _playerService.open(
        normalizedValue,
        play: SourceOpenPolicy.shouldAutoplayOnOpen(
          forcePlay: forcePlay,
          autoPlaySetting: _settings.autoPlay,
        ),
      );
    } catch (e) {
      final failureKind = SourceLoadFailurePolicy.classify(e);
      _log(
        SourceLoadFailurePolicy.logEvent(failureKind),
        message: e.toString(),
        detailsBuilder: () => {'source': normalizedValue},
        severity: failureKind == SourceLoadFailureKind.permissionDenied
            ? DebugSeverity.warn
            : DebugSeverity.error,
      );
      if (!_playback.isLoadCurrent(gen)) return;
      if (mounted) {
        setState(_player.clearSourceOnLoadFailure);
        unawaited(_seekPreviewService.setSource(null));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failureKind == SourceLoadFailureKind.permissionDenied
                  ? AppLocalizations.of(context).snackFileLoadPermissionDenied
                  : AppLocalizations.of(context).snackFileLoadFailed,
            ),
          ),
        );
      }
      return;
    } finally {
      _player.fileOpenInProgress = false;
    }

    final postOpen = SourceLoadPostOpenPolicy.plan(
      isLoadCurrent: _playback.isLoadCurrent(gen),
      isDisposed: _isDisposed,
      mounted: mounted,
      normalizedSource: normalizedSource,
      isAudioFile: _player.isAudioFile,
    );
    if (!postOpen.shouldProceed) {
      return;
    }
    _cacheTracksForCurrentLoad(_playerService.currentTracks);

    // Load the same source into the seek preview service (no-op when the
    // feature is disabled or for audio-only files).
    final seekPreviewPath = postOpen.seekPreviewPath;
    if (seekPreviewPath != null) {
      unawaited(_seekPreviewService.setSource(seekPreviewPath));
    } else {
      unawaited(_seekPreviewService.setSource(null));
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
      final shouldPersistRecent = postOpen.shouldPersistRecent;
      if (shouldPersistRecent) {
        _settings.addRecentFile(normalizedValue);
      }
      if (postOpen.shouldRememberOpenDirectory) {
        _rememberLastOpenDirectory(normalizedValue);
      }
      _log(
        postOpen.recentPersistLogEvent,
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

    if (postOpen.shouldRefreshUi) {
      setState(() {});
    }

    // Apply post-load settings: equalizer, multi-audio mix, refresh chapters,
    // and publish to media session.
    _player.resumePathInProgress = postOpen.resumeTrackingPath;
    _syncSpectrumService(_player.isPlaying);
    unawaited(_refreshChapters());
    unawaited(_applyMultiAudioMix());
    if (postOpen.shouldApplyResume) {
      unawaited(_maybeApplyResume(normalizedValue));
    }
    unawaited(
      _mediaSession.updateMetadata(
        title: normalizedSource.displayName,
        duration: _player.duration,
      ),
    );
  }

  void _cacheTracksForCurrentLoad(
    Tracks tracks, {
    bool refreshChapters = false,
  }) {
    final result = _player.cacheTracksForLoad(
      tracks,
      mixLoadState: _mixLoadState,
      multiAudioMixEnabled: _settings.multiAudioMix,
      refreshChapters: refreshChapters,
    );
    if (result.audioOnlyChanged) {
      setState(() {});
    }
    if (result.refreshChapters) {
      unawaited(_refreshChaptersIfNeeded());
    }
    if (result.shouldRefreshMix) {
      unawaited(_applyMultiAudioMix());
    }
  }

  void _onDragDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final rawCount = details.files.length;
    final paths = details.files
        .map(
          (f) => PlayerPathUtils.normalizeDropPath(
            f.path,
            windows: Platform.isWindows,
          ),
        )
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    final droppedCount = rawCount - paths.length;
    if (paths.isEmpty) {
      _log(
        'drop_file_invalid_path',
        detailsBuilder: () => {'count': rawCount},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).snackCouldNotReadDroppedFile,
            ),
          ),
        );
      }
      return;
    }
    _log(
      'drop_file_received',
      detailsBuilder: () => {
        'path': paths.first,
        'count': paths.length,
        'skipped': droppedCount,
      },
    );
    if (droppedCount > 0 && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            droppedCount == 1
                ? l10n.snackSkippedUnreadableFile
                : l10n.snackSkippedUnreadableFiles(droppedCount),
          ),
        ),
      );
    }
    switch (DropFilePolicy.action(validPathCount: paths.length)) {
      case DropFileAction.none:
        return;
      case DropFileAction.loadSingle:
        unawaited(_loadFile(paths.first));
      case DropFileAction.enqueuePlayNow:
        _enqueue(paths, playNow: true);
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
    _settings.pruneRecentFiles();
    _log('recent_file_open_requested', detailsBuilder: () => {'path': path});
    final source = PlayableSource.fromStored(path);
    if (source == null) return;
    if (source.isUrl) {
      unawaited(_loadSource(source));
    } else {
      unawaited(_openRequestedFile(source.value));
    }
  }

  Future<void> _reopenLastFile() async {
    _settings.pruneRecentFiles();
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
      await _loadSource(source);
    } else {
      await _openRequestedFile(source.value);
    }
  }

  void _rememberLastOpenDirectory(String filePath) {
    final dir = p.dirname(filePath).trim();
    if (dir.isEmpty || dir == '.') return;
    _settings.lastOpenDirectory = dir;
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
                color: visuals.overlayColor.withValues(alpha: maskOpacity),
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final hk = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.f1 ||
            (event.logicalKey == LogicalKeyboardKey.question) ||
            (event.logicalKey == LogicalKeyboardKey.slash &&
                hk.isShiftPressed))) {
      unawaited(_showKeybindsDialog());
      return KeyEventResult.handled;
    }
    final custom = _settings.keybinds;
    final shortcut = PlayerShortcutsService.resolve(
      event: event,
      hasMedia: _currentFile != null,
      isMetaPressed: hk.isMetaPressed,
      isControlPressed: hk.isControlPressed,
      isShiftPressed: hk.isShiftPressed,
      isAltPressed: hk.isAltPressed,
      customBindings: custom.isEmpty ? null : custom,
    );

    switch (shortcut) {
      case PlayerShortcutAction.openFile:
        _log('shortcut_open_file', category: DebugLogCategory.ui);
        _openFile();
        return KeyEventResult.handled;
      case PlayerShortcutAction.reopenLast:
        _log('shortcut_reopen_last', category: DebugLogCategory.ui);
        unawaited(_reopenLastFile());
        return KeyEventResult.handled;
      case PlayerShortcutAction.playPause:
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
        _seekRelative(_seekStep);
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekBack:
        _log('shortcut_seek_back', category: DebugLogCategory.ui);
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
        unawaited(_toggleFullscreen());
        return KeyEventResult.handled;
      case PlayerShortcutAction.exitFullscreen:
        _log('shortcut_exit_fullscreen', category: DebugLogCategory.ui);
        unawaited(_exitFullscreen());
        return KeyEventResult.handled;
      case PlayerShortcutAction.chapterNext:
        _log('shortcut_chapter_next', category: DebugLogCategory.ui);
        unawaited(_stepChapter(1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.chapterPrev:
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
      case null:
        return KeyEventResult.ignored;
    }
  }

  double _volumeBeforeMute = 100.0;

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
    _audioSpectrum.resetDynamics();
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
    _log(
      wasMuted ? 'mute_disabled' : 'mute_enabled',
      detailsBuilder: () => wasMuted
          ? {'restored_volume': toggle.newVolume}
          : {'previous_volume': toggle.volumeBeforeMute},
    );
  }

  bool _fullscreenToggleInFlight = false;

  Future<void> _toggleFullscreen() async {
    if (_fullscreenToggleInFlight) return;
    _fullscreenToggleInFlight = true;
    try {
      final enabled = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!enabled);
      // Verify state actually changed (Wayland / tiling WMs may reject).
      final actual = await windowManager.isFullScreen();
      if (actual == enabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).snackFullscreenRejected),
            duration: _snackbarShortDuration,
          ),
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
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        endDrawer: _buildPlayQueueDrawer(),
        body: GlassShellBackground(
          child: Column(
            children: [
              const CustomTitleBar(),
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
                            AnimatedSwitcher(
                              duration: _contentSwitchDuration,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ...previousChildren,
                                    ...(currentChild == null
                                        ? const <Widget>[]
                                        : <Widget>[currentChild]),
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                final fade = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                );
                                final scale = Tween<double>(
                                  begin: 0.985,
                                  end: 1.0,
                                ).animate(fade);
                                return FadeTransition(
                                  opacity: fade,
                                  child: ScaleTransition(
                                    scale: scale,
                                    child: child,
                                  ),
                                );
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onDoubleTap: _currentFile == null
                                    ? null
                                    : () {
                                        _log(
                                          'media_surface_double_tap',
                                          category: DebugLogCategory.ui,
                                        );
                                        unawaited(_toggleFullscreen());
                                      },
                                child: MouseRegion(
                                  onHover: (_) => _pulseOsd(),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: _buildMediaSurface(),
                                      ),
                                      if (_currentFile != null &&
                                          _settings.osdEnabled)
                                        Positioned.fill(
                                          child: OsdOverlay(
                                            title: _player.osdTitle(),
                                            position: _player.position,
                                            duration: _player.duration,
                                            visible: _player.osdVisible,
                                            transientMessage:
                                                PlayerController.stripOsdTimestamp(
                                                  _player.osdTransientMessage,
                                                ),
                                          ),
                                        ),
                                      if (_currentFile != null &&
                                          PlayerUiPolicies.showAudioSpectrum(
                                            settings: _settings,
                                            isAudioFile: _player.isAudioFile,
                                          ))
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          height: 40,
                                          child: AudioSpectrumVisualizer(
                                            isPlaying: _player.isPlaying,
                                            position: _player.position,
                                            duration: _player.duration,
                                            spectrumStream:
                                                _audioSpectrum.spectrumStream,
                                          ),
                                        ),
                                      if (_compactMode)
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: CompactExitButton(
                                            onPressed: () =>
                                                unawaited(_toggleCompactMode()),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: AnimatedOpacity(
                                duration: _animFastDuration,
                                curve: Curves.easeOutCubic,
                                opacity: _isDragging ? 1 : 0,
                                child: ClipRect(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 8.0,
                                      sigmaY: 8.0,
                                    ),
                                    child: ColoredBox(
                                      color: context
                                          .windowVisuals
                                          .dragOverlayColor
                                          .withValues(alpha: 0.28),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.file_download,
                                              size: 64,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Drop media files to play or enqueue',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildBottomDock(),
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
    return GlassChrome(
      borderOnTop: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: _seekBarSizeDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _player.duration.inMilliseconds > 0
                ? Padding(
                    key: const ValueKey('seek-visible'),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          PlayerController.formatDuration(_player.position),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Expanded(
                          child: SeekSliderWithHover(
                            position: _player.position,
                            duration: _player.duration,
                            previewService: _seekPreviewService,
                            previewEnabled: PlayerUiPolicies.showSeekPreview(
                              settings: _settings,
                              isAudioFile: _player.isAudioFile,
                            ),
                            onSeekStart: () => _player.isSeeking = true,
                            onSeekChange: (value) {
                              setState(() {
                                _player.position = Duration(
                                  milliseconds: value.toInt(),
                                );
                              });
                            },
                            onSeekEnd: (value) {
                              _player.isSeeking = false;
                              unawaited(
                                _playerService
                                    .seek(Duration(milliseconds: value.toInt()))
                                    .catchError((Object e) {
                                      _log(
                                        'seek_slider_failed',
                                        message: e.toString(),
                                        severity: DebugSeverity.warn,
                                      );
                                    }),
                              );
                            },
                          ),
                        ),
                        Text(
                          PlayerController.formatDuration(_player.duration),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('seek-hidden'),
                    width: double.infinity,
                  ),
          ),
          TransportControls(
            isPlaying: _player.isPlaying,
            volume: _player.volume,
            hasMedia: _currentFile != null,
            speed: _settings.speed,
            loopMode: _settings.loopMode,
            recentFiles: _settings.recentFiles,
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
              await _playerService.stop();
              unawaited(_seekPreviewService.setSource(null));
              setState(_player.clearMediaSurface);
            },
            onOpenFile: _openFile,
            onOpenFolder: () => unawaited(_openFolder()),
            onOpenUrl: PlayerUiPolicies.showOpenUrlButton(_settings)
                ? () => unawaited(_openUrl())
                : null,
            onReopenLast: () {
              _log(
                'control_reopen_last_pressed',
                category: DebugLogCategory.ui,
              );
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
          ),
        ],
      ),
    );
  }

  Widget _buildPlayQueueDrawer() {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassDrawerBody(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _playlist,
            builder: (context, _) {
              final items = _playlist.items;
              return Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Icon(Icons.queue_music, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.dialogPlayQueueTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: l10n.tooltipMediaInfo,
                          onPressed: _currentFile == null
                              ? null
                              : () => unawaited(_showMediaInfoDialog()),
                        ),
                        if (items.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_all),
                            tooltip: l10n.actionClear,
                            onPressed: () {
                              _playlist.clear();
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // List
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              l10n.dialogPlayQueueEmpty,
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.54,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final isCurrent = index == _playlist.index;
                              final source = items[index];
                              final name = source.displayName;

                              return QueueItemTile(
                                name: name,
                                isCurrent: isCurrent,
                                isUrl: source.isUrl,
                                playLabel: l10n.actionPlay,
                                removeLabel: l10n.actionRemove,
                                colorScheme: colorScheme,
                                onActivate: () {
                                  _playlist.jumpTo(index);
                                  unawaited(_loadSource(source));
                                },
                                onRemove: () {
                                  unawaited(_removeQueueItem(index));
                                },
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  // Actions at bottom
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _pickFilesToEnqueue,
                          icon: const Icon(Icons.add),
                          label: Text(l10n.dialogPlayQueueAddFiles),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('queue-add-folder-button'),
                          onPressed: () => unawaited(
                            _openFolder(playNow: _playlist.isEmpty),
                          ),
                          icon: const Icon(Icons.create_new_folder),
                          label: Text(l10n.buttonOpenFolder),
                        ),
                        if (items.isNotEmpty)
                          FilledButton.tonalIcon(
                            key: const Key('queue-remove-missing-button'),
                            onPressed: () =>
                                unawaited(_removeMissingQueueItems()),
                            icon: const Icon(Icons.cleaning_services),
                            label: Text(l10n.actionRemoveMissing),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDropZone() {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: _buildCenterPanel(
        maxWidth: 440,
        children: [
          _buildCenterIconSurface(
            icon: Icons.music_note,
            size: 40,
            color: colorScheme.primary.withValues(alpha: 0.88),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.emptyStateMessage,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.74),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.folder_open),
                label: Text(l10n.buttonOpenFile),
              ),
              FilledButton.tonalIcon(
                key: const Key('open-folder-empty-button'),
                onPressed: () => unawaited(_openFolder()),
                icon: const Icon(Icons.create_new_folder),
                label: Text(l10n.buttonOpenFolder),
              ),
              if (_settings.experimentalFeaturesEnabled)
                FilledButton.tonalIcon(
                  key: const Key('open-url-empty-button'),
                  onPressed: () => unawaited(_openUrl()),
                  icon: const Icon(Icons.link),
                  label: Text(l10n.buttonOpenUrl),
                ),
              FilledButton.tonalIcon(
                key: const Key('reopen-last-empty-button'),
                onPressed: _reopenLastFile,
                icon: const Icon(Icons.history),
                label: Text(l10n.buttonReopenLast),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel({
    required List<Widget> children,
    double maxWidth = 560,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassPanel(
        maxWidth: maxWidth,
        padding: const EdgeInsets.fromLTRB(32, 34, 32, 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  Widget _buildCenterIconSurface({
    required IconData icon,
    required double size,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final visuals = context.windowVisuals;
    final glass = visuals.isGlass;

    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: glass
            ? RadialGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.20),
                  colorScheme.primary.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: glass ? null : colorScheme.primary.withValues(alpha: 0.14),
        boxShadow: glass
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: glass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    visuals.panelTopColor.withValues(alpha: 0.92),
                    visuals.panelBottomColor.withValues(alpha: 0.88),
                  ],
                )
              : null,
          color: glass ? null : colorScheme.surface.withValues(alpha: 0.52),
          border: Border.all(
            color: glass
                ? visuals.panelBorderColor
                : colorScheme.primary.withValues(alpha: 0.22),
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }

  Widget _buildMediaSurface() {
    if (_currentFile == null) {
      return KeyedSubtree(
        key: const ValueKey('media-drop-zone'),
        child: _buildDropZone(),
      );
    }

    if (_player.isAudioFile) {
      final showAlbumArt = _player.hasAlbumArtTrack;
      return KeyedSubtree(
        key: ValueKey(showAlbumArt ? 'media-audio-with-art' : 'media-audio'),
        child: _buildAudioBackground(showAlbumArt: showAlbumArt),
      );
    }

    return Container(
      key: const ValueKey('media-video'),
      color: Colors.black,
      child: _buildVideoSurface(),
    );
  }

  Widget _buildVideoSurface({BoxFit fit = BoxFit.contain, Color? fill}) {
    final controller = _videoController;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: fit,
      fill: fill ?? Colors.transparent,
    );
  }

  Widget _buildAudioBackground({required bool showAlbumArt}) {
    final source = _player.currentSource;
    final fileName = source == null
        ? ''
        : (source.isFile
              ? p.basenameWithoutExtension(source.value)
              : source.displayName);
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final visualizerHeight = PlayerUiPolicies.spectrumHeight(_settings);
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final shortestSideSize = shortestSide.clamp(220.0, 360.0).toDouble();
        final maxByHeight = (constraints.maxHeight - 260 - visualizerHeight)
            .clamp(170.0, 360.0);
        final albumArtSize = math.min(shortestSideSize, maxByHeight);

        return Padding(
          padding: EdgeInsets.only(bottom: visualizerHeight),
          child: Center(
            child: _buildCenterPanel(
              maxWidth: 700,
              children: [
                if (showAlbumArt)
                  _buildAlbumArtSurface(size: albumArtSize)
                else
                  _buildCenterIconSurface(
                    icon: Icons.album,
                    size: 54,
                    color: colorScheme.primary.withValues(alpha: 0.88),
                  ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    fileName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.of(context).labelAudioPlayback,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumArtSurface({required double size}) {
    final visuals = context.windowVisuals;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visuals.panelBorderColor),
        boxShadow: [
          BoxShadow(
            color: visuals.shadowColor,
            blurRadius: visuals.isGlass ? 28 : 24,
            offset: Offset(0, visuals.isGlass ? 16 : 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: visuals.contentColor,
          child: _buildVideoSurface(
            fit: BoxFit.cover,
            fill: Colors.transparent,
          ),
        ),
      ),
    );
  }

  // ── OSD ────────────────────────────────────────────────────

  void _pulseOsd() {
    if (!OsdPolicy.shouldShow(
      osdEnabled: _settings.osdEnabled,
      mounted: mounted,
    )) {
      return;
    }
    if (!_player.osdVisible) setState(() => _player.osdVisible = true);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(_osdHideDuration, () {
      if (mounted) setState(() => _player.osdVisible = false);
    });
  }

  void _showOsdMessage(String msg) {
    if (!OsdPolicy.shouldShow(
      osdEnabled: _settings.osdEnabled,
      mounted: mounted,
    )) {
      return;
    }
    setState(
      () => _player.osdTransientMessage = OsdPolicy.formatTransientMessage(msg),
    );
  }

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
    await _playerService.setAudioTrack(next);
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
    await _playerService.setSubtitleTrack(next);
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
      await _playerService.setSubtitleTrack(SubtitleTrack.no());
      _player.subtitlesVisible = false;
      _showOsdMessage(l10n.osdSubtitlesOff);
    } else {
      final candidate = tracks.subtitle.firstWhere(
        (t) => t.id != 'no' && t.id != 'auto',
        orElse: SubtitleTrack.auto,
      );
      await _playerService.setSubtitleTrack(candidate);
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
        fallbackLabel: AppLocalizations.of(
          context,
        ).trackFallbackLabel(fallbackId),
      );

  // ── Chapters ──────────────────────────────────────────────

  Future<void> _refreshChapters({int? expectedCount}) async {
    final l10n = AppLocalizations.of(context);
    final list = await ChapterListLoader.load(
      readProperty: _playerService.getProperty,
      expectedCount: expectedCount,
      fallbackTitle: (i) => l10n.chapterFallbackLabel(i + 1),
    );
    if (!mounted) return;
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
    await _playerService.setChapter(next);
    _showOsdMessage(l10n.osdChapter(_player.chapters[next].title));
  }

  // ── Screenshot ────────────────────────────────────────────

  Future<void> _takeScreenshot() async {
    final l10n = AppLocalizations.of(context);
    final source = _player.currentSource;
    if (source == null) return;
    final fmt = _settings.screenshotFormat;
    final mime = fmt == 'png' ? 'image/png' : 'image/jpeg';
    final bytes = await _playerService.screenshot(format: mime);
    if (bytes == null) {
      _showOsdMessage(l10n.osdScreenshotFailed);
      return;
    }
    final dir = _settings.screenshotDir ?? _defaultScreenshotDir();
    try {
      Directory(dir).createSync(recursive: true);
    } catch (e) {
      _log(
        'screenshot_dir_create_failed',
        message: e.toString(),
        details: {'dir': dir},
        severity: DebugSeverity.warn,
      );
    }
    final rawBase = source.isFile
        ? p.basenameWithoutExtension(source.value)
        : source.displayName;
    final base = rawBase
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final outPath = p.join(dir, '${base.isEmpty ? 'dacx' : base}_$ts.$fmt');
    try {
      await File(outPath).writeAsBytes(bytes, flush: true);
      _showOsdMessage(l10n.osdScreenshotSaved);
      _log(
        'screenshot_saved',
        detailsBuilder: () => {'path': outPath, 'bytes': bytes.length},
      );
    } catch (e) {
      _showOsdMessage(l10n.osdScreenshotSaveFailed);
      _log(
        'screenshot_save_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  String _defaultScreenshotDir() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, 'Pictures', 'DACX');
  }

  // ── Equalizer ─────────────────────────────────────────────

  Future<void> _applyEqualizer() async {
    await _applyMergedAudioFilters();
  }

  /// Builds and applies the combined af chain: EQ + spectrum analysis.
  Future<void> _applyMergedAudioFilters() async {
    final spectrumWanted =
        _settings.audioWaveformEnabled &&
        _player.isAudioFile &&
        _audioSpectrum.isActive;
    final result = await AudioFilterChain.apply(
      lastAppliedChain: _player.lastAppliedAfChain,
      eqEnabled: _settings.eqEnabled,
      eqBands: _settings.eqBands,
      spectrumWanted: spectrumWanted,
      setAudioFilter: _playerService.setAudioFilter,
    );
    if (result.skipped) return;

    _player.lastAppliedAfChain = result.appliedChain;

    if (result.spectrumInstalled) {
      _audioSpectrum.confirmFilterInstalled();
    } else if (result.spectrumFailed) {
      _audioSpectrum.confirmFilterFailed();
    }

    if (result.failed) {
      _log(
        'audio_filter_apply_failed',
        detailsBuilder: () => {'chain': result.appliedChain},
        severity: DebugSeverity.warn,
      );
    }
  }

  /// Start or stop spectrum polling based on playing state + settings.
  /// Always applies the merged af chain once at the end.
  void _syncSpectrumService(bool playing) {
    final action = SpectrumSyncPolicy.resolve(
      playing: playing,
      isAudioFile: _player.isAudioFile,
      audioWaveformEnabled: _settings.audioWaveformEnabled,
      spectrumCurrentlyActive: _audioSpectrum.isActive,
    );
    switch (action) {
      case SpectrumSyncAction.startAndApply:
        unawaited(
          _audioSpectrum.start().then((_) => _applyMergedAudioFilters()),
        );
      case SpectrumSyncAction.stopAndApply:
        unawaited(
          _audioSpectrum.stop().then((_) => _applyMergedAudioFilters()),
        );
      case SpectrumSyncAction.applyOnly:
        unawaited(_applyMergedAudioFilters());
    }
  }

  void _toggleEqualizer() {
    _settings.eqEnabled = !_settings.eqEnabled;
    unawaited(_applyEqualizer());
    final l10n = AppLocalizations.of(context);
    _showOsdMessage(
      l10n.osdEqualizer(
        _settings.eqEnabled ? l10n.osdStateOn : l10n.osdStateOff,
      ),
    );
  }

  String _eqPresetLabel(AppLocalizations l10n, String id) {
    return switch (id) {
      'flat' => l10n.eqPresetFlat,
      'bass_boost' => l10n.eqPresetBassBoost,
      'bass_reduce' => l10n.eqPresetBassReduce,
      'treble_boost' => l10n.eqPresetTrebleBoost,
      'vocal' => l10n.eqPresetVocal,
      'rock' => l10n.eqPresetRock,
      'electronic' => l10n.eqPresetElectronic,
      'acoustic' => l10n.eqPresetAcoustic,
      'loudness' => l10n.eqPresetLoudness,
      'classical' => l10n.eqPresetClassical,
      _ => id,
    };
  }

  // ── Multi-audio mix ───────────────────────────────────────

  Future<void> _applyMultiAudioMix({bool announce = false}) async {
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final ids = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .toList(growable: false);
    final shouldMix = _settings.multiAudioMix && ids.length >= 2;
    if (!shouldMix) {
      // Always clear the property in case a previous file left a graph.
      await _playerService.setProperty('lavfi-complex', '');
      if (_player.mixActive) {
        _player.mixActive = false;
        if (announce) {
          _showOsdMessage(l10n.osdAudioMixOff);
        }
      }
      return;
    }
    // Validate IDs are numeric — mpv's lavfi-complex labels are [aid<N>]
    // where <N> must be the integer track-id reported in track-list.
    final invalid = ids.where((id) => int.tryParse(id) == null).toList();
    if (invalid.isNotEmpty) {
      _log(
        'multi_audio_mix_invalid_ids',
        message: 'non-numeric audio track ids: ${invalid.join(',')}',
        severity: DebugSeverity.warn,
      );
      if (announce) {
        _showOsdMessage(l10n.osdAudioMixUnsupportedIds);
      }
      return;
    }
    final videoIds = tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .where((id) => int.tryParse(id) != null)
        .toList(growable: false);
    final chain = PlaybackMixPolicy.buildLavfiComplex(
      audioIds: ids,
      videoTrackId: videoIds.isNotEmpty ? videoIds.first : null,
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
    if (ok) {
      final wasActive = _player.mixActive;
      _player.mixActive = true;
      if (announce || !wasActive) {
        _showOsdMessage(l10n.osdAudioMixActive(ids.length));
      }
    } else {
      _player.mixActive = false;
      _log('multi_audio_mix_setproperty_failed', severity: DebugSeverity.warn);
      if (announce) {
        _showOsdMessage(l10n.osdAudioMixFailed);
      }
    }
  }

  Future<void> _reloadCurrentForMixChange() async {
    final source = _player.currentSource;
    if (source == null) return;
    if (_mixReloadInFlight) return;
    _mixReloadInFlight = true;
    try {
      final savedPos = _player.position;
      await _loadSource(source);
      if (savedPos > Duration.zero) {
        await Future<void>.delayed(_mixReloadDelay);
        if (mounted && _player.position < _resumeStartThreshold) {
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
          _audioSpectrum.resetDynamics();
          unawaited(_playerService.seek(target));
        }
      case MediaSessionDispatchKind.setLoopMode:
        final mode = dispatch.loopMode;
        if (mode != null) {
          _settings.loopMode = mode;
        }
      case MediaSessionDispatchKind.setShuffle:
        final on = dispatch.shuffle;
        if (on != null) {
          _settings.playlistShuffle = on;
          _playlist.setShuffle(on);
        }
      case MediaSessionDispatchKind.setVolume:
        final pct = dispatch.volumePercent;
        if (pct != null) {
          setState(() {
            _player.volume = pct;
          });
          _settings.volume = pct;
          unawaited(_playerService.setVolume(pct).catchError((_) {}));
        }
      case MediaSessionDispatchKind.setRate:
        final rate = dispatch.rate;
        if (rate != null) {
          _settings.speed = rate;
        }
      case MediaSessionDispatchKind.noop:
        break;
    }
  }

  Future<void> _stopPlaybackAndResetUi() async {
    await _playerService.stop();
    if (!mounted || _isDisposed) return;
    setState(_player.resetTransport);
    _audioSpectrum.resetDynamics();
    _syncSpectrumService(false);
  }

  // ── Resume position ─────────────────────────────────

  void _persistResumePosition() {
    if (!_settings.resumePlaybackEnabled) return;
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

  Future<void> _maybeApplyResume(String path) async {
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
      if (_isDisposed || _currentFile != path) return;
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
    try {
      await _playerService.seek(Duration(milliseconds: ms!));
      if (mounted) {
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
    final wrap = _settings.loopMode == LoopMode.loop;
    final next = _playlist.advance(delta, wrap: wrap);
    if (next == null) return;
    final l10n = AppLocalizations.of(context);
    _showOsdMessage(delta > 0 ? l10n.osdNextInQueue : l10n.osdPreviousInQueue);
    await _loadSource(next);
  }

  void _enqueue(List<String> paths, {bool playNow = false}) {
    _enqueueSources(
      paths.map(PlayableSource.file).toList(growable: false),
      playNow: playNow,
    );
  }

  void _enqueueSources(List<PlayableSource> sources, {bool playNow = false}) {
    if (sources.isEmpty) return;
    switch (EnqueuePolicy.mode(
      playNow: playNow,
      playlistEmpty: _playlist.isEmpty,
    )) {
      case EnqueueMode.replaceAndPlay:
        final dropped = _playlist.replaceSources(sources);
        if (dropped > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).snackQueueTruncated(PlaylistService.maxQueueItems, dropped),
              ),
            ),
          );
        }
        final first = _playlist.current;
        if (first != null) unawaited(_loadSource(first));
      case EnqueueMode.append:
        final dropped = _playlist.addAllSources(sources);
        _showOsdMessage(
          sources.length == 1
              ? AppLocalizations.of(context).osdAddedToQueue
              : AppLocalizations.of(
                  context,
                ).osdAddedMultipleToQueue(sources.length),
        );
        if (dropped > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).snackQueueTruncated(PlaylistService.maxQueueItems, dropped),
              ),
            ),
          );
        }
    }
  }

  Future<void> _removeMissingQueueItems() async {
    final before = _playlist.current;
    final removed = await _playlist.removeMissingFiles();
    if (!mounted) return;
    if (_playlist.isEmpty) {
      unawaited(_stopPlaybackAndResetUi());
    } else if (before != null && _playlist.current != before) {
      final next = _playlist.current;
      if (next != null) {
        unawaited(_loadSource(next));
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).snackQueueRemovedMissing(removed),
        ),
      ),
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
    await _loadSource(next);
  }

  // ── Compact / mini-player mode ────────────────────────────

  Future<void> _toggleCompactMode() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    final l10n = AppLocalizations.of(context);
    if (_compactMode) {
      // Restore window state.
      try {
        if (_preCompactSize != null) {
          await windowManager.setSize(_preCompactSize!);
        }
        if (_preCompactPos != null) {
          await windowManager.setPosition(_preCompactPos!);
        }
        await windowManager.setAlwaysOnTop(_preCompactAlwaysOnTop);
      } catch (e) {
        _log(
          'compact_mode_restore_failed',
          category: DebugLogCategory.ui,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }
      setState(() => _compactMode = false);
      _showOsdMessage(l10n.osdMiniPlayerOff);
    } else {
      try {
        _preCompactSize = await windowManager.getSize();
        _preCompactPos = await windowManager.getPosition();
        _preCompactAlwaysOnTop = _settings.alwaysOnTop;
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
        await windowManager.setSize(_compactWindowSize);
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        _log(
          'compact_mode_enter_failed',
          category: DebugLogCategory.ui,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }
      setState(() => _compactMode = true);
      _showOsdMessage(l10n.osdMiniPlayerOn);
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

    await showDialog<void>(
      context: context,
      builder: (ctx) => MediaInfoDialog(
        width: _dialogWidth(ctx, 520),
        fields: [
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
    final l10n = AppLocalizations.of(context);
    final tracks = _player.currentTracks;
    final hasAudioOptions = tracks != null && tracks.audio.length > 1;
    final hasSubOptions = tracks != null && tracks.subtitle.isNotEmpty;
    if (_player.chapters.isEmpty) await _refreshChapters();
    if (!mounted) return;
    final hasChapters = _player.chapters.isNotEmpty;

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppLocalizations.of(context).dismissBarrierLabel,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      transitionDuration: _sheetTransitionDuration,
      pageBuilder: (ctx, _, _) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final experimentalAmber = Color.lerp(cs.tertiary, Colors.amber, 0.72)!;
        final experimentalBackground = Color.alphaBlend(
          experimentalAmber.withValues(alpha: isDark ? 0.16 : 0.11),
          cs.surface,
        );
        final experimentalBorder = experimentalAmber.withValues(
          alpha: isDark ? 0.45 : 0.36,
        );
        final experimentalIcon = Color.lerp(
          experimentalAmber,
          isDark ? Colors.amber.shade200 : Colors.amber.shade700,
          0.22,
        )!;
        // Build the menu items as a compact, right-aligned vertical panel.
        Widget item({
          required IconData icon,
          required String label,
          required String action,
          Widget? trailing,
        }) {
          return InkWell(
            onTap: () => Navigator.pop(ctx, action),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: cs.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
                  ?trailing,
                ],
              ),
            ),
          );
        }

        Widget switchItem({
          required IconData icon,
          required String label,
          required bool value,
          required ValueChanged<bool> onChanged,
          bool experimental = false,
        }) {
          final child = InkWell(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: experimental ? experimentalIcon : cs.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(value: value, onChanged: onChanged),
                  ),
                ],
              ),
            ),
          );
          if (!experimental) return child;
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: experimentalBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: experimentalBorder),
              ),
              child: child,
            ),
          );
        }

        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 64),
            child: Material(
              color: cs.surface.withValues(alpha: 0.97),
              elevation: 12,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 240,
                  maxWidth: 280,
                  maxHeight: 520,
                ),
                child: StatefulBuilder(
                  builder: (ctx, setSheetState) {
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasAudioOptions)
                            item(
                              icon: Icons.audiotrack,
                              label: l10n.dialogAudioTrackTitle,
                              action: 'audio',
                            ),
                          if (hasSubOptions)
                            item(
                              icon: Icons.subtitles,
                              label: l10n.dialogSubtitleTrackTitle,
                              action: 'subtitle',
                            ),
                          if (hasChapters)
                            item(
                              icon: Icons.menu_book,
                              label: l10n.dialogChaptersTitle,
                              action: 'chapters',
                            ),
                          item(
                            icon: Icons.graphic_eq,
                            label: l10n.dialogEqualizerTitle,
                            action: 'equalizer',
                          ),
                          if (_currentFile != null && !_player.isAudioFile)
                            item(
                              icon: Icons.photo_camera,
                              label: l10n.menuTakeScreenshot,
                              action: 'screenshot',
                            ),
                          if (hasAudioOptions &&
                              _settings.experimentalFeaturesEnabled)
                            switchItem(
                              icon: Icons.multitrack_audio,
                              label: l10n.menuMixAllAudioTracks,
                              value: _settings.multiAudioMix,
                              experimental: true,
                              onChanged: (v) {
                                _settings.multiAudioMix = v;
                                setSheetState(() {});
                                unawaited(() async {
                                  await _applyMultiAudioMix(announce: true);
                                  if (_currentFile != null) {
                                    await _reloadCurrentForMixChange();
                                  }
                                }());
                              },
                            ),
                          if (!_player.isAudioFile &&
                              (_player.currentSource?.isFile ?? false))
                            switchItem(
                              icon: Icons.image_search,
                              label: l10n.menuSeekThumbnailsBeta,
                              value: _settings.seekPreviewEnabled,
                              onChanged: (v) {
                                _settings.seekPreviewEnabled = v;
                                setSheetState(() {});
                                unawaited(
                                  _seekPreviewService.setEnabled(v).then((_) {
                                    final source = _player.currentSource;
                                    if (v && source != null && source.isFile) {
                                      return _seekPreviewService.setSource(
                                        source.value,
                                      );
                                    }
                                    return null;
                                  }),
                                );
                                if (mounted) setState(() {});
                              },
                            ),
                          item(
                            icon: Icons.keyboard,
                            label: l10n.dialogKeyboardShortcutsTitle,
                            action: 'keybinds',
                          ),
                          const Divider(height: 1),
                          item(
                            icon: Icons.queue_music,
                            label: _playlist.isEmpty
                                ? l10n.menuQueueEmpty
                                : l10n.menuQueueCount(_playlist.length),
                            action: 'queue',
                          ),
                          item(
                            icon: Icons.playlist_add,
                            label: l10n.menuAddFilesToQueue,
                            action: 'enqueue',
                          ),
                          switchItem(
                            icon: Icons.shuffle,
                            label: l10n.menuShuffleQueue,
                            value: _settings.playlistShuffle,
                            onChanged: (v) {
                              _settings.playlistShuffle = v;
                              _playlist.setShuffle(v);
                              setSheetState(() {});
                            },
                          ),
                          switchItem(
                            icon: Icons.picture_in_picture_alt,
                            label: l10n.menuMiniPlayer,
                            value: _compactMode,
                            onChanged: (_) => Navigator.pop(ctx, 'compact'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.15, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
    if (!mounted) return;
    switch (result) {
      case 'audio':
        unawaited(_showAudioTracksDialog());
        break;
      case 'subtitle':
        unawaited(_showSubtitleTracksDialog());
        break;
      case 'chapters':
        unawaited(_showChaptersDialog());
        break;
      case 'equalizer':
        unawaited(_showEqualizerDialog());
        break;
      case 'screenshot':
        unawaited(_takeScreenshot());
        break;
      case 'keybinds':
        unawaited(_showKeybindsDialog());
        break;
      case 'queue':
        _scaffoldKey.currentState?.openEndDrawer();
        break;
      case 'enqueue':
        unawaited(_pickFilesToEnqueue());
        break;
      case 'shuffle':
        // already toggled inline
        break;
      case 'compact':
        unawaited(_toggleCompactMode());
        break;
    }
  }

  Future<void> _showAudioTracksDialog() async {
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    final current = _player.currentTrackSelection?.audio.id;
    final selected = await showDialog<AudioTrack>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(ctx).dialogAudioTrackTitle),
        children: list
            .map(
              (t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Icon(
                      t.id == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _trackLabel(t.title, t.language, t.id),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      await _disableMixForManualTrackSelection();
      await _playerService.setAudioTrack(selected);
    }
  }

  Future<void> _showSubtitleTracksDialog() async {
    final tracks = _player.currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    final current = _player.currentTrackSelection?.subtitle.id;
    final selected = await showDialog<SubtitleTrack>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(ctx).dialogSubtitleTrackTitle),
        children: list
            .map(
              (t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Icon(
                      t.id == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.id == 'no'
                            ? AppLocalizations.of(ctx).subtitleTrackOff
                            : _trackLabel(t.title, t.language, t.id),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      await _playerService.setSubtitleTrack(selected);
      _player.subtitlesVisible = selected.id != 'no';
    }
  }

  Future<void> _showChaptersDialog() async {
    if (_player.chapters.isEmpty) await _refreshChapters();
    if (!mounted || _player.chapters.isEmpty) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(ctx).dialogChaptersTitle),
        children: _player.chapters
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.index),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        PlayerController.formatDuration(c.time),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(c.title, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null) {
      await _playerService.setChapter(picked);
    }
  }

  Future<void> _showEqualizerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final l10n = AppLocalizations.of(ctx);
            final bands = List<double>.from(_settings.eqBands);
            return AlertDialog(
              title: Text(l10n.dialogEqualizerTitle),
              content: SizedBox(
                width: _dialogWidth(ctx, 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(l10n.dialogEqualizerEnable),
                        const Spacer(),
                        Switch(
                          value: _settings.eqEnabled,
                          onChanged: (v) {
                            _settings.eqEnabled = v;
                            unawaited(_applyEqualizer());
                            setLocal(() {});
                          },
                        ),
                      ],
                    ),
                    DropdownButton<String>(
                      value: _settings.eqPreset,
                      isExpanded: true,
                      onChanged: (id) {
                        if (id == null) return;
                        final preset = EqualizerService.presetById(id);
                        if (preset == null) return;
                        _settings.eqPreset = id;
                        _settings.eqBands = preset.gains;
                        unawaited(_applyEqualizer());
                        setLocal(() {});
                      },
                      items: kEqPresets
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(_eqPresetLabel(l10n, p.id)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: math.min(
                        220.0,
                        math.max(120.0, _dialogHeight(ctx, 360) - 140),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(SettingsService.eqBandCount, (
                          i,
                        ) {
                          final freq = SettingsService.eqBandFrequencies[i];
                          final label = freq < 1000
                              ? '$freq'
                              : '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k';
                          return Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Slider(
                                      min: -12,
                                      max: 12,
                                      divisions: 48,
                                      value: bands[i],
                                      onChanged: (v) {
                                        bands[i] = v;
                                        _settings.eqBands = bands;
                                        _settings.eqPreset = 'custom';
                                        unawaited(_applyEqualizer());
                                        setLocal(() {});
                                      },
                                    ),
                                  ),
                                ),
                                Text(
                                  label,
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                                Text(
                                  '${bands[i].toStringAsFixed(0)}dB',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _settings.eqBands = List<double>.filled(
                      SettingsService.eqBandCount,
                      0,
                    );
                    _settings.eqPreset = 'flat';
                    unawaited(_applyEqualizer());
                    setLocal(() {});
                  },
                  child: Text(l10n.actionReset),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.actionClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickFilesToEnqueue() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.media);
      if (result == null) return;
      final paths = result.paths
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) return;
      _enqueue(paths);
    } catch (e) {
      _log(
        'enqueue_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
    }
  }

  Future<void> _showKeybindsDialog() async {
    final current = Map<String, List<String>>.from(_settings.keybinds);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final l10n = AppLocalizations.of(ctx);
            return AlertDialog(
              title: Text(l10n.dialogKeyboardShortcutsTitle),
              content: SizedBox(
                width: _dialogWidth(ctx, 460),
                height: _dialogHeight(ctx, 480),
                child: Scrollbar(
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Text(
                          AppLocalizations.of(ctx).keybindsTip,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                      ...PlayerShortcutAction.values.map((a) {
                        final accels =
                            current[a.name] ??
                            defaultKeybinds[a]?.toList(growable: true) ??
                            const <String>[];
                        return ListTile(
                          dense: true,
                          title: Text(
                            shortcutActionLabel(
                              a,
                              l10n: AppLocalizations.of(ctx),
                            ),
                          ),
                          subtitle: Text(
                            accels.isEmpty
                                ? AppLocalizations.of(ctx).keybindsNone
                                : accels.join(', '),
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: l10n.actionSetNewBinding,
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () async {
                                  final accel = await _captureKeybind(ctx);
                                  if (accel == null) return;
                                  current[a.name] = [accel];
                                  _settings.keybinds = current;
                                  setLocal(() {});
                                },
                              ),
                              IconButton(
                                tooltip: l10n.actionResetToDefault,
                                icon: const Icon(Icons.refresh, size: 18),
                                onPressed: () {
                                  current.remove(a.name);
                                  _settings.keybinds = current;
                                  setLocal(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _settings.resetKeybinds();
                    current.clear();
                    setLocal(() {});
                  },
                  child: Text(l10n.actionResetAll),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.actionClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _captureKeybind(BuildContext context) async {
    final node = FocusNode();
    String? captured;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l10n.dialogKeyCaptureTitle),
            content: SizedBox(
              width: _dialogWidth(ctx, 320),
              child: Focus(
                autofocus: true,
                focusNode: node,
                onKeyEvent: (n, e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey != LogicalKeyboardKey.controlLeft &&
                      e.logicalKey != LogicalKeyboardKey.controlRight &&
                      e.logicalKey != LogicalKeyboardKey.shiftLeft &&
                      e.logicalKey != LogicalKeyboardKey.shiftRight &&
                      e.logicalKey != LogicalKeyboardKey.altLeft &&
                      e.logicalKey != LogicalKeyboardKey.altRight &&
                      e.logicalKey != LogicalKeyboardKey.metaLeft &&
                      e.logicalKey != LogicalKeyboardKey.metaRight) {
                    captured = PlayerShortcutsService.acceleratorFromEvent(e);
                    setLocal(() {});
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  child: Text(
                    captured ?? 'Waiting…',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.actionCancel),
              ),
              TextButton(
                onPressed: captured == null ? null : () => Navigator.pop(ctx),
                child: Text(l10n.actionSave),
              ),
            ],
          );
        },
      ),
    );
    node.dispose();
    return captured;
  }
}
