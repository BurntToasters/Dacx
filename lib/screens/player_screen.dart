import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

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
import '../services/settings_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/debug_log_service.dart';
import '../services/equalizer_service.dart';
import '../services/media_session_service.dart';
import '../services/playlist_service.dart';
import '../services/seek_preview_service.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/osd_overlay.dart';
import '../widgets/seek_slider.dart';
import '../widgets/transport_controls.dart';
import 'settings_screen.dart';

const _audioExtensions = {
  'mp3',
  'flac',
  'wav',
  'ogg',
  'aac',
  'm4a',
  'wma',
  'opus',
  'ape',
  'alac',
};

const _macOpenFileMethodChannel = MethodChannel(
  'run.rosie.dacx/open_file/methods',
);
const _macOpenFileEventChannel = EventChannel(
  'run.rosie.dacx/open_file/events',
);

class PlayerScreen extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final String? initialFile;

  const PlayerScreen({
    super.key,
    required this.settings,
    required this.debugLog,
    this.initialFile,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerService _playerService;
  late final VideoController _videoController;
  late final UpdateService _updateService;
  late final SeekPreviewService _seekPreviewService;

  SettingsService get _settings => widget.settings;

  String? _currentFile;
  bool _isDragging = false;
  bool _isAudioFile = false;
  bool _hasVideoOutput = false;
  bool _hasAlbumArtTrack = false;
  String? _albumArtTrackId;
  bool _mixActive = false;
  List<String>? _cachedAudioIds;
  List<String>? _cachedVideoIds;
  bool _mixReloadInFlight = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _volume = 100.0;
  bool _isSeeking = false;
  int _loadGen = 0;

  static const _supportedExtensions = {
    ..._audioExtensions,
    'mp4',
    'mkv',
    'avi',
    'webm',
    'mov',
    'wmv',
    'flv',
    'm4v',
  };

  final List<StreamSubscription> _subscriptions = [];
  Future<void> _loadQueue = Future<void>.value();
  bool _isDisposed = false;

  // Tracks / chapters / OSD state
  Tracks? _currentTracks;
  Track? _currentTrackSelection;
  List<_ChapterInfo> _chapters = const [];
  bool _subtitlesVisible = true;
  bool _osdVisible = false;
  String? _osdTransientMessage;
  Timer? _osdHideTimer;
  late final MediaSessionService _mediaSession;
  late final PlaylistService _playlist;

  // Compact mini-player mode (PiP-style on desktop).
  bool _compactMode = false;
  Size? _preCompactSize;
  Offset? _preCompactPos;
  bool _preCompactAlwaysOnTop = false;
  static const Size _compactWindowSize = Size(480, 320);

  // Resume-position bookkeeping.
  Timer? _resumeSaveTimer;
  String? _resumePathInProgress;

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

  @override
  void initState() {
    super.initState();
    _updateService = UpdateService(
      debugLog: widget.debugLog,
      debugSource: 'player_screen',
    );
    _playerService = PlayerService();
    _seekPreviewService = SeekPreviewService();
    unawaited(
      _seekPreviewService.setEnabled(_settings.seekPreviewEnabled),
    );
    _settings.pruneRecentFiles(notifyListeners: false);
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
    _videoController = VideoController(
      _playerService.player,
      configuration: VideoControllerConfiguration(
        hwdec: hwDec,
        enableHardwareAcceleration: hwEnabled,
      ),
    );
    _volume = _settings.volume;
    _log(
      'player_init',
      detailsBuilder: () => {
        'auto_play': _settings.autoPlay,
        'volume': _volume.toStringAsFixed(2),
        'speed': _settings.speed.toStringAsFixed(2),
        'loop_mode': _settings.loopMode.name,
      },
    );

    // Apply saved playback settings.
    unawaited(
      _playerService.setVolume(_volume).catchError((Object e) {
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

    _subscriptions.addAll([
      _playerService.positionStream.listen((pos) {
        if (!mounted || _isDisposed || _isSeeking) return;
        final dMs = (pos.inMilliseconds - _position.inMilliseconds).abs();
        final shouldRender =
            dMs >= 200 || (pos.inSeconds != _position.inSeconds);
        if (shouldRender) {
          setState(() => _position = pos);
        } else {
          _position = pos;
        }
        if (_settings.mediaSessionEnabled) {
          unawaited(
            _mediaSession.updatePosition(pos, playing: _isPlaying),
          );
        }
      }),
      _playerService.durationStream.listen((dur) {
        if (!mounted || _isDisposed) return;
        setState(() => _duration = dur);
        if (dur.inMilliseconds > 0 && _settings.mediaSessionEnabled) {
          final path = _currentFile;
          if (path != null) {
            unawaited(
              _mediaSession.updateMetadata(
                title: p.basenameWithoutExtension(path),
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
        setState(() => _isPlaying = playing);
        if (_settings.mediaSessionEnabled) {
          unawaited(_mediaSession.updatePosition(_position, playing: playing));
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
        setState(() => _volume = vol);
        if (widget.debugLog.isEnabled) {
          _log(
            'volume_stream_updated',
            detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
          );
        }
      }),
      _playerService.player.stream.width.listen((w) {
        if (!mounted || _isDisposed) return;
        final has = w != null && w > 0;
        if (has != _hasVideoOutput) {
          setState(() => _hasVideoOutput = has);
          if (widget.debugLog.isEnabled) {
            _log(
              'video_output_changed',
              detailsBuilder: () => {'has_video_output': has, 'width': w},
            );
          }
        }
      }),
      _playerService.player.stream.tracks.listen((tracks) {
        if (!mounted || _isDisposed) return;
        _currentTracks = tracks;
        final albumArtTrack = _firstEmbeddedAlbumArtTrack(tracks);
        final hasAlbumArt = albumArtTrack != null;
        final nextTrackId = albumArtTrack?.id;
        final trackChanged = nextTrackId != _albumArtTrackId;
        final hasArtChanged = hasAlbumArt != _hasAlbumArtTrack;

        if (hasArtChanged || trackChanged) {
          setState(() {
            _hasAlbumArtTrack = hasAlbumArt;
            _albumArtTrackId = nextTrackId;
          });
          _log(
            'album_art_track_changed',
            detailsBuilder: () => {
              'has_album_art_track': hasAlbumArt,
              'track_id': nextTrackId,
            },
          );
        }

        if (!_isAudioFile || !trackChanged) return;

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
      _playerService.tracksStream.listen((tracks) {
        if (!mounted || _isDisposed) return;
        unawaited(_refreshChapters());
        // Cache numeric ids so the next open() can pre-set lavfi-complex.
        final aIds = tracks.audio
            .where((t) => t.id != 'auto' && t.id != 'no')
            .map((t) => t.id)
            .where((id) => int.tryParse(id) != null)
            .toList(growable: false);
        final vIds = tracks.video
            .where((t) => t.id != 'auto' && t.id != 'no')
            .map((t) => t.id)
            .where((id) => int.tryParse(id) != null)
            .toList(growable: false);
        if (aIds.isNotEmpty) _cachedAudioIds = aIds;
        if (vIds.isNotEmpty) _cachedVideoIds = vIds;
        if (_settings.multiAudioMix &&
            aIds.length >= 2 &&
            !_mixActive &&
            !_mixReloadInFlight) {
          unawaited(_reloadCurrentForMixChange());
        }
      }),
      _playerService.completedStream.listen((completed) {
        if (!mounted || _isDisposed || !completed) return;
        setState(() => _position = Duration.zero);
        if (widget.debugLog.isEnabled) {
          _log('playback_completed');
        }
        // File ran to end → drop saved resume position.
        if (_currentFile != null) {
          _settings.saveResumePosition(_currentFile!, null);
        }
        // Try to advance the playlist (loop-mode `none` only).
        if (_settings.loopMode == LoopMode.none) {
          unawaited(_advancePlaylist(1, fromCompletion: true));
        }
      }),
      _playerService.trackStream.listen((track) {
        if (!mounted || _isDisposed) return;
        _currentTrackSelection = track;
      }),
    ]);

    // Media session
    _mediaSession = MediaSessionService(debugLog: widget.debugLog);
    unawaited(
      _mediaSession.init(enabled: _settings.mediaSessionEnabled),
    );
    _subscriptions.add(_mediaSession.commands.listen(_onMediaSessionCommand));

    // Playlist (in-memory; reflects shuffle from settings).
    _playlist = PlaylistService()..setShuffle(_settings.playlistShuffle);

    // Periodic resume-position saver (every 5s while playing).
    _resumeSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _persistResumePosition(),
    );

    // Listen for settings changes (speed, loop, always-on-top).
    _settings.addListener(_onSettingsChanged);
    _initializePlatformFileOpenBridge();

    _checkForUpdates();

    // Auto-open CLI file.
    if (widget.initialFile != null) {
      _log(
        'initial_file_requested',
        detailsBuilder: () => {'path': widget.initialFile},
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openRequestedFile(widget.initialFile!));
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
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    unawaited(_mediaSession.dispose());
    _playlist.dispose();
    try {
      _videoController.player.dispose();
    } catch (_) {}
    unawaited(_seekPreviewService.dispose());
    unawaited(_playerService.dispose());
    super.dispose();
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
    _applySpeed(_settings.speed);
    _applyLoopMode(_settings.loopMode);
    unawaited(_applyEqualizer());
    unawaited(_applyMultiAudioMix());
    unawaited(_mediaSession.setEnabled(_settings.mediaSessionEnabled));
    unawaited(
      windowManager.setAlwaysOnTop(_settings.alwaysOnTop).catchError((
        Object e,
      ) {
        _log(
          'always_on_top_apply_failed',
          category: DebugLogCategory.system,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _initializePlatformFileOpenBridge() {
    if (!Platform.isMacOS) return;
    _log('mac_open_file_bridge_init', category: DebugLogCategory.system);
    unawaited(_bootstrapMacOpenFileBridge());
  }

  Future<void> _bootstrapMacOpenFileBridge() async {
    if (_isDisposed) return;
    try {
      final pending = await _macOpenFileMethodChannel.invokeListMethod<dynamic>(
        'getPendingFiles',
      );
      if (_isDisposed || !mounted) return;
      if (pending != null && pending.isNotEmpty) {
        _log(
          'mac_pending_files_found',
          category: DebugLogCategory.system,
          detailsBuilder: () => {'count': pending.length},
        );
        for (final entry in pending) {
          if (_isDisposed || !mounted) return;
          final path = _coerceOpenPath(entry);
          if (path == null) continue;
          await _openRequestedFile(path);
        }
      }
    } on MissingPluginException {
      _log(
        'mac_open_file_bridge_missing_plugin',
        category: DebugLogCategory.system,
        severity: DebugSeverity.warn,
      );
      return;
    } on PlatformException {
      // Ignore if the native bridge is unavailable.
      _log(
        'mac_open_file_bridge_platform_exception',
        category: DebugLogCategory.system,
        severity: DebugSeverity.warn,
      );
      return;
    } catch (e) {
      _log(
        'mac_open_file_bridge_failed',
        category: DebugLogCategory.system,
        message: e.toString(),
        severity: DebugSeverity.error,
      );
    }

    if (_isDisposed || !mounted) return;
    _subscriptions.add(
      _macOpenFileEventChannel.receiveBroadcastStream().listen(
        (event) {
          if (_isDisposed || !mounted) return;
          final path = _coerceOpenPath(event);
          if (path != null) {
            _log(
              'mac_open_file_event_received',
              category: DebugLogCategory.system,
              detailsBuilder: () => {'path': path},
            );
            unawaited(_openRequestedFile(path));
          }
        },
        onError: (error) {
          _log(
            'mac_open_file_event_error',
            category: DebugLogCategory.system,
            message: error.toString(),
            severity: DebugSeverity.warn,
          );
        },
      ),
    );
  }

  String? _coerceOpenPath(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _openRequestedFile(String filePath) async {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return;
    if (_currentFile == trimmed) {
      _log(
        'open_requested_same_file_ignored',
        detailsBuilder: () => {'path': trimmed},
      );
      return;
    }
    _log('open_requested', detailsBuilder: () => {'path': trimmed});
    await _loadFile(trimmed);
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
    try {
      final nativePlayer = _playerService.player.platform;
      if (nativePlayer is NativePlayer) {
        nativePlayer.setProperty('hwdec', value);
        _log(
          'hwdec_property_applied',
          category: DebugLogCategory.hwaccel,
          detailsBuilder: () => {'hwdec': value},
        );
      }
    } catch (_) {
      // hwdec may not be available on all platforms.
      _log(
        'hwdec_property_failed',
        category: DebugLogCategory.hwaccel,
        detailsBuilder: () => {'hwdec': value},
        severity: DebugSeverity.warn,
      );
    }
  }

  void _applyLoopMode(LoopMode mode) {
    final plMode = switch (mode) {
      LoopMode.none => PlaylistMode.none,
      LoopMode.single => PlaylistMode.single,
      LoopMode.loop => PlaylistMode.loop,
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

  // ── Update check with cooldown ────────────────────────────

  Future<void> _checkForUpdates() async {
    if (!_settings.shouldCheckForUpdate) return;
    _log(
      'launch_update_check_started',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'last_check_epoch': _settings.lastUpdateCheck},
    );
    final update = await _updateService.checkForUpdate();
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
    _log(
      'update_snackbar_shown',
      category: DebugLogCategory.update,
      detailsBuilder: () => {'version': update.version},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dacx v${update.version} is available'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _updateService.openReleasePage(update.url),
        ),
      ),
    );
  }

  // ── File handling ─────────────────────────────────────────

  Future<void> _openFile() async {
    _log('file_picker_open_requested');
    try {
      final initialDirectory = _settings.lastOpenDirectory;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        lockParentWindow: true,
        allowMultiple: false,
        initialDirectory: initialDirectory,
      );

      if (result == null) {
        _log('file_picker_cancelled');
        return;
      }
      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _log('file_picker_invalid_path', severity: DebugSeverity.warn);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read selected file path.')),
          );
        }
        return;
      }

      await _loadFile(path);
    } on PlatformException catch (e) {
      _log(
        'file_picker_platform_exception',
        message: e.message ?? e.code,
        severity: DebugSeverity.error,
      );
      if (mounted) {
        final detail = e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : e.code;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File picker failed. $detail')));
      }
    } catch (e) {
      _log(
        'file_picker_failed',
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open file picker.')),
        );
      }
    }
  }

  Future<void> _loadFile(String filePath) {
    _loadQueue = _loadQueue
        .catchError((_) {})
        .then((_) => _loadFileInternal(filePath));
    return _loadQueue;
  }

  Future<void> _loadFileInternal(String filePath) async {
    if (_isDisposed) return;
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      _log(
        'file_load_invalid_path',
        detailsBuilder: () => {'path': filePath},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid file path. Try another file.')),
        );
      }
      return;
    }

    if (!File(normalizedPath).existsSync()) {
      _log(
        'file_load_missing',
        detailsBuilder: () => {'path': normalizedPath},
        severity: DebugSeverity.warn,
      );
      _settings.pruneRecentFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File not found. It may have moved or been deleted.'),
          ),
        );
      }
      return;
    }

    final ext = p.extension(normalizedPath).toLowerCase().replaceFirst('.', '');
    _log(
      'file_load_started',
      detailsBuilder: () => {'path': normalizedPath, 'extension': ext},
    );
    if (!_supportedExtensions.contains(ext)) {
      _log(
        'file_load_unsupported_extension',
        detailsBuilder: () => {'extension': ext, 'path': normalizedPath},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unsupported file type. Open an audio/video file.'),
          ),
        );
      }
      return;
    }
    final gen = ++_loadGen;
    if (!mounted || _isDisposed) return;
    // Persist resume position for the previous file before switching.
    _persistResumePosition();
    _resumePathInProgress = null;
    setState(() {
      _currentFile = normalizedPath;
      _isAudioFile = _audioExtensions.contains(ext);
      _hasVideoOutput = false;
      _hasAlbumArtTrack = false;
      _albumArtTrackId = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _log(
      'media_type_initial_state',
      detailsBuilder: () => {
        'is_audio_file': _isAudioFile,
        'has_video_output': false,
      },
    );

    try {
      String preOpenLavfi = '';
      if (_settings.multiAudioMix &&
          _cachedAudioIds != null &&
          _cachedAudioIds!.length >= 2) {
        final aIds = _cachedAudioIds!;
        final inputs = aIds.map((id) => '[aid$id]').join(' ');
        final audioBranch =
            '$inputs amix=inputs=${aIds.length}:normalize=0 [ao]';
        if (_cachedVideoIds != null && _cachedVideoIds!.isNotEmpty) {
          preOpenLavfi =
              '[vid${_cachedVideoIds!.first}] null [vo] ; $audioBranch';
        } else {
          preOpenLavfi = audioBranch;
        }
      }
      await _playerService.setProperty('lavfi-complex', preOpenLavfi);
      _mixActive = preOpenLavfi.isNotEmpty;
      await _playerService.open(normalizedPath, play: _settings.autoPlay);
    } catch (e) {
      final permissionDenied = _isPermissionDeniedError(e);
      _log(
        permissionDenied ? 'file_load_permission_denied' : 'file_load_failed',
        message: e.toString(),
        detailsBuilder: () => {'path': normalizedPath},
        severity: permissionDenied ? DebugSeverity.warn : DebugSeverity.error,
      );
      if (gen != _loadGen) return;
      if (mounted) {
        setState(() {
          _currentFile = null;
          _isAudioFile = false;
          _albumArtTrackId = null;
        });
        _resumePathInProgress = null;
        unawaited(_seekPreviewService.setSource(null));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              permissionDenied
                  ? 'Permission denied. Check file access and try again.'
                  : 'Could not open file. Try another file.',
            ),
          ),
        );
      }
      return;
    }

    if (gen != _loadGen || _isDisposed) return;

    // Load the same source into the seek preview service (no-op when the
    // feature is disabled or for audio-only files).
    if (!_isAudioFile) {
      unawaited(_seekPreviewService.setSource(normalizedPath));
    } else {
      unawaited(_seekPreviewService.setSource(null));
    }

    _log(
      'file_load_succeeded',
      detailsBuilder: () => {
        'path': normalizedPath,
        'auto_play': _settings.autoPlay,
      },
    );

    try {
      _settings.addRecentFile(normalizedPath);
      _rememberLastOpenDirectory(normalizedPath);
      _log(
        'recent_file_added',
        category: DebugLogCategory.settings,
        detailsBuilder: () => {'path': normalizedPath},
      );
    } catch (e) {
      _log(
        'recent_file_persist_failed',
        category: DebugLogCategory.settings,
        message: e.toString(),
        detailsBuilder: () => {'path': normalizedPath},
        severity: DebugSeverity.warn,
      );
    }

    if (mounted && !_isDisposed && gen == _loadGen) {
      setState(() {});
    }

    // Apply post-load settings: equalizer, multi-audio mix, refresh chapters,
    // and publish to media session.
    _resumePathInProgress = normalizedPath;
    unawaited(_applyEqualizer());
    unawaited(_refreshChapters());
    unawaited(_applyMultiAudioMix());
    unawaited(_maybeApplyResume(normalizedPath));
    unawaited(
      _mediaSession.updateMetadata(
        title: p.basenameWithoutExtension(normalizedPath),
        duration: _duration,
      ),
    );
  }

  void _onDragDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final paths = details.files
        .map((f) => f.path)
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      _log('drop_file_invalid_path', severity: DebugSeverity.warn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read dropped file path.')),
        );
      }
      return;
    }
    _log(
      'drop_file_received',
      detailsBuilder: () => {'path': paths.first, 'count': paths.length},
    );
    if (paths.length == 1) {
      unawaited(_loadFile(paths.first));
    } else {
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
    unawaited(_openRequestedFile(path));
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
    await _openRequestedFile(lastPath);
  }

  void _rememberLastOpenDirectory(String filePath) {
    final dir = p.dirname(filePath).trim();
    if (dir.isEmpty || dir == '.') return;
    _settings.lastOpenDirectory = dir;
  }

  bool _isPermissionDeniedError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('permission denied') ||
        lower.contains('access is denied') ||
        lower.contains('operation not permitted')) {
      return true;
    }
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code == 1 || code == 5 || code == 13) {
        return true;
      }
    }
    return false;
  }

  // ── Navigation ────────────────────────────────────────────

  void _openSettings() {
    _log('open_settings_requested', category: DebugLogCategory.ui);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            SettingsScreen(settings: _settings, debugLog: widget.debugLog),
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
        _seekRelative(const Duration(seconds: 5));
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekBack:
        _log('shortcut_seek_back', category: DebugLogCategory.ui);
        _seekRelative(const Duration(seconds: -5));
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
      case null:
        return KeyEventResult.ignored;
    }
  }

  double _volumeBeforeMute = 100.0;

  void _seekRelative(Duration offset) {
    if (_duration.inMilliseconds == 0) return;
    var target = _position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
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
    final newVol = (_volume + delta).clamp(0.0, 100.0);
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
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      unawaited(
        _playerService.setVolume(0).catchError((Object e) {
          _log(
            'mute_toggle_failed',
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }),
      );
      _settings.volume = 0;
      _log(
        'mute_enabled',
        detailsBuilder: () => {'previous_volume': _volumeBeforeMute},
      );
    } else {
      unawaited(
        _playerService.setVolume(_volumeBeforeMute).catchError((Object e) {
          _log(
            'mute_toggle_failed',
            message: e.toString(),
            severity: DebugSeverity.warn,
          );
        }),
      );
      _settings.volume = _volumeBeforeMute;
      _log(
        'mute_disabled',
        detailsBuilder: () => {'restored_volume': _volumeBeforeMute},
      );
    }
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
          const SnackBar(
            content: Text('Fullscreen change rejected by window manager.'),
            duration: Duration(seconds: 2),
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

  // ── Formatting ────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [visuals.windowTopColor, visuals.windowBottomColor],
            ),
          ),
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
                              duration: const Duration(milliseconds: 240),
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
                                            title: _osdTitle,
                                            position: _position,
                                            duration: _duration,
                                            visible: _osdVisible,
                                            transientMessage:
                                                _stripOsdTimestamp(
                                              _osdTransientMessage,
                                            ),
                                          ),
                                        ),
                                      if (_compactMode)
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: _CompactExitButton(
                                            onPressed: () => unawaited(
                                              _toggleCompactMode(),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 140),
                                curve: Curves.easeOutCubic,
                                opacity: _isDragging ? 1 : 0,
                                child: ColoredBox(
                                  color: visuals.dragOverlayColor,
                                  child: const Center(
                                    child: Icon(
                                      Icons.file_download,
                                      size: 64,
                                      color: Colors.white,
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
    final visuals = context.windowVisuals;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: visuals.barColor,
        border: Border(top: BorderSide(color: visuals.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _duration.inMilliseconds > 0
                ? Padding(
                    key: const ValueKey('seek-visible'),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Expanded(
                          child: SeekSliderWithHover(
                            position: _position,
                            duration: _duration,
                            previewService: _seekPreviewService,
                            previewEnabled: _settings.seekPreviewEnabled &&
                                !_isAudioFile,
                            onSeekStart: () => _isSeeking = true,
                            onSeekChange: (value) {
                              setState(() {
                                _position =
                                    Duration(milliseconds: value.toInt());
                              });
                            },
                            onSeekEnd: (value) {
                              _isSeeking = false;
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
                          _formatDuration(_duration),
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
            isPlaying: _isPlaying,
            volume: _volume,
            hasMedia: _currentFile != null,
            speed: _settings.speed,
            loopMode: _settings.loopMode,
            recentFiles: _settings.recentFiles,
            onPlayPause: () async {
              _log('control_play_pause_pressed', category: DebugLogCategory.ui);
              try {
                await _playerService.playPause();
              } catch (_) {}
            },
            onStop: () async {
              _log('control_stop_pressed', category: DebugLogCategory.ui);
              await _playerService.stop();
              unawaited(_seekPreviewService.setSource(null));
              setState(() {
                _currentFile = null;
                _isAudioFile = false;
                _hasVideoOutput = false;
                _hasAlbumArtTrack = false;
                _albumArtTrackId = null;
                _position = Duration.zero;
                _duration = Duration.zero;
              });
            },
            onOpenFile: _openFile,
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
              } catch (_) {}
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
          ),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    final colorScheme = Theme.of(context).colorScheme;

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
            'Drop a file here or click Open',
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
                label: const Text('Open File'),
              ),
              FilledButton.tonalIcon(
                key: const Key('reopen-last-empty-button'),
                onPressed: _reopenLastFile,
                icon: const Icon(Icons.history),
                label: const Text('Reopen Last'),
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
    final visuals = context.windowVisuals;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(32, 34, 32, 38),
          decoration: BoxDecoration(
            color: visuals.contentColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: visuals.borderColor),
            boxShadow: [
              BoxShadow(
                color: visuals.shadowColor,
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
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

    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primary.withValues(alpha: 0.14),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.surface.withValues(alpha: 0.52),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.22),
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

    if (_isAudioFile) {
      final showAlbumArt = _hasAlbumArtTrack;
      return KeyedSubtree(
        key: ValueKey(showAlbumArt ? 'media-audio-with-art' : 'media-audio'),
        child: _buildAudioBackground(showAlbumArt: showAlbumArt),
      );
    }

    return Container(
      key: const ValueKey('media-video'),
      color: Colors.black,
      child: Video(controller: _videoController, controls: NoVideoControls),
    );
  }

  Widget _buildAudioBackground({required bool showAlbumArt}) {
    final fileName = _currentFile != null
        ? p.basenameWithoutExtension(_currentFile!)
        : '';
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final shortestSideSize = shortestSide.clamp(220.0, 360.0).toDouble();
        final maxByHeight = (constraints.maxHeight - 260).clamp(170.0, 360.0);
        final albumArtSize = math.min(shortestSideSize, maxByHeight);

        return Center(
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
                'Audio playback',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.62),
                  height: 1.2,
                ),
              ),
            ],
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
        border: Border.all(color: visuals.borderColor),
        boxShadow: [
          BoxShadow(
            color: visuals.shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: visuals.contentColor,
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
            fit: BoxFit.cover,
            fill: Colors.transparent,
          ),
        ),
      ),
    );
  }

  VideoTrack? _firstEmbeddedAlbumArtTrack(Tracks tracks) {
    for (final track in tracks.video) {
      final id = track.id.toLowerCase();
      if (id == 'auto' || id == 'no') continue;
      if (track.albumart == true || track.image == true) {
        return track;
      }
    }
    return null;
  }

  // ── OSD ────────────────────────────────────────────────────

  void _pulseOsd() {
    if (!_settings.osdEnabled) return;
    if (!mounted) return;
    if (!_osdVisible) setState(() => _osdVisible = true);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _osdVisible = false);
    });
  }

  void _showOsdMessage(String msg) {
    if (!_settings.osdEnabled || !mounted) return;
    setState(() => _osdTransientMessage = '$msg\u2009·\u2009${DateTime.now().millisecondsSinceEpoch}');
    // include timestamp suffix to force OSD to register a fresh message even
    // when the underlying text is identical to the previous transient
  }

  String get _osdTitle {
    if (_currentFile == null) return '';
    return p.basenameWithoutExtension(_currentFile!);
  }

  String _stripOsdTimestamp(String? raw) {
    if (raw == null) return '';
    final i = raw.indexOf('\u2009·\u2009');
    return i == -1 ? raw : raw.substring(0, i);
  }

  // ── Tracks: audio / subtitle cycling ──────────────────────

  Future<void> _cycleAudioTrack() async {
    final tracks = _currentTracks;
    if (tracks == null || tracks.audio.length <= 1) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (list.isEmpty) return;
    final current = _currentTrackSelection?.audio.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next = list[(idx + 1) % list.length];
    await _disableMixForManualTrackSelection();
    await _playerService.setAudioTrack(next);
    _showOsdMessage('Audio: ${_trackLabel(next.title, next.language, next.id)}');
  }

  Future<void> _cycleSubtitleTrack() async {
    final tracks = _currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    if (list.length <= 1) return;
    final current = _currentTrackSelection?.subtitle.id;
    final idx = list.indexWhere((t) => t.id == current);
    final next = list[(idx + 1) % list.length];
    await _playerService.setSubtitleTrack(next);
    _subtitlesVisible = next.id != 'no';
    _showOsdMessage(
      next.id == 'no'
          ? 'Subtitles: Off'
          : 'Subtitles: ${_trackLabel(next.title, next.language, next.id)}',
    );
  }

  Future<void> _toggleSubtitleVisibility() async {
    final tracks = _currentTracks;
    if (tracks == null) return;
    if (_subtitlesVisible) {
      await _playerService.setSubtitleTrack(SubtitleTrack.no());
      _subtitlesVisible = false;
      _showOsdMessage('Subtitles: Off');
    } else {
      final candidate = tracks.subtitle.firstWhere(
        (t) => t.id != 'no' && t.id != 'auto',
        orElse: SubtitleTrack.auto,
      );
      await _playerService.setSubtitleTrack(candidate);
      _subtitlesVisible = true;
      _showOsdMessage(
        'Subtitles: ${_trackLabel(candidate.title, candidate.language, candidate.id)}',
      );
    }
  }

  String _trackLabel(String? title, String? language, String fallbackId) {
    final parts = <String>[];
    if (title != null && title.trim().isNotEmpty) parts.add(title.trim());
    if (language != null && language.trim().isNotEmpty) parts.add(language.trim());
    if (parts.isEmpty) return 'Track $fallbackId';
    return parts.join(' · ');
  }

  // ── Chapters ──────────────────────────────────────────────

  Future<void> _refreshChapters() async {
    final raw = await _playerService.getProperty('chapter-list/count');
    final count = int.tryParse(raw ?? '') ?? 0;
    if (count <= 0) {
      if (_chapters.isNotEmpty && mounted) setState(() => _chapters = const []);
      return;
    }
    final list = <_ChapterInfo>[];
    for (var i = 0; i < count; i++) {
      final title = await _playerService.getProperty('chapter-list/$i/title');
      final timeStr = await _playerService.getProperty('chapter-list/$i/time');
      final time = double.tryParse(timeStr ?? '') ?? 0;
      list.add(_ChapterInfo(
        index: i,
        title: (title == null || title.isEmpty) ? 'Chapter ${i + 1}' : title,
        time: Duration(milliseconds: (time * 1000).round()),
      ));
    }
    if (mounted) setState(() => _chapters = list);
  }

  Future<void> _stepChapter(int delta) async {
    if (_chapters.isEmpty) {
      await _refreshChapters();
    }
    if (_chapters.isEmpty) return;
    final current = await _playerService.getProperty('chapter');
    final idx = int.tryParse(current ?? '') ?? 0;
    final next = (idx + delta).clamp(0, _chapters.length - 1);
    await _playerService.setChapter(next);
    _showOsdMessage('Chapter: ${_chapters[next].title}');
  }

  // ── Screenshot ────────────────────────────────────────────

  Future<void> _takeScreenshot() async {
    if (_currentFile == null) return;
    final fmt = _settings.screenshotFormat;
    final mime = fmt == 'png' ? 'image/png' : 'image/jpeg';
    final bytes = await _playerService.screenshot(format: mime);
    if (bytes == null) {
      _showOsdMessage('Screenshot failed');
      return;
    }
    final dir = _settings.screenshotDir ?? _defaultScreenshotDir();
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {}
    final base = p.basenameWithoutExtension(_currentFile!);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final outPath = p.join(dir, '${base}_$ts.$fmt');
    try {
      await File(outPath).writeAsBytes(bytes, flush: true);
      _showOsdMessage('Screenshot saved');
      _log(
        'screenshot_saved',
        detailsBuilder: () => {'path': outPath, 'bytes': bytes.length},
      );
    } catch (e) {
      _showOsdMessage('Screenshot save failed');
      _log(
        'screenshot_save_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
    }
  }

  String _defaultScreenshotDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, 'Pictures', 'DACX');
  }

  // ── Equalizer ─────────────────────────────────────────────

  Future<void> _applyEqualizer() async {
    if (!_settings.eqEnabled) {
      await _playerService.setAudioFilter('');
      return;
    }
    final chain = EqualizerService.buildAfChain(_settings.eqBands);
    await _playerService.setAudioFilter(chain);
  }

  void _toggleEqualizer() {
    _settings.eqEnabled = !_settings.eqEnabled;
    unawaited(_applyEqualizer());
    _showOsdMessage('Equalizer: ${_settings.eqEnabled ? 'On' : 'Off'}');
  }

  // ── Multi-audio mix ───────────────────────────────────────

  Future<void> _applyMultiAudioMix({bool announce = false}) async {
    final tracks = _currentTracks;
    if (tracks == null) return;
    final ids = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .toList(growable: false);
    final shouldMix = _settings.multiAudioMix && ids.length >= 2;
    if (!shouldMix) {
      // Always clear the property in case a previous file left a graph.
      await _playerService.setProperty('lavfi-complex', '');
      if (_mixActive) {
        _mixActive = false;
        if (announce) _showOsdMessage('Audio mix off');
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
      if (announce) _showOsdMessage('Cannot mix: unsupported track ids');
      return;
    }
    final inputs = ids.map((id) => '[aid$id]').join(' ');
    final audioChain = '$inputs amix=inputs=${ids.length}:normalize=0 [ao]';
    String chain = audioChain;
    final videoIds = tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no')
        .map((t) => t.id)
        .where((id) => int.tryParse(id) != null)
        .toList(growable: false);
    if (videoIds.isNotEmpty) {

      chain = '[vid${videoIds.first}] null [vo] ; $audioChain';
    }
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
      final wasActive = _mixActive;
      _mixActive = true;
      if (announce || !wasActive) {
        _showOsdMessage('Mixing ${ids.length} audio tracks');
      }
    } else {
      _mixActive = false;
      _log(
        'multi_audio_mix_setproperty_failed',
        severity: DebugSeverity.warn,
      );
      if (announce) _showOsdMessage('Could not enable audio mix');
    }
  }

  Future<void> _reloadCurrentForMixChange() async {
    final path = _currentFile;
    if (path == null) return;
    if (_mixReloadInFlight) return;
    _mixReloadInFlight = true;
    try {
      final savedPos = _position;
      await _loadFile(path);
      if (savedPos > Duration.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (mounted && _position < const Duration(seconds: 1)) {
          unawaited(_playerService.seek(savedPos));
        }
      }
    } finally {
      _mixReloadInFlight = false;
    }
  }

  Future<void> _disableMixForManualTrackSelection() async {
    if (!_settings.multiAudioMix && !_mixActive) return;
    final wasActive = _mixActive;
    if (_settings.multiAudioMix) {
      _settings.multiAudioMix = false;
    }
    await _playerService.setProperty('lavfi-complex', '');
    _mixActive = false;
    if (wasActive) {
      await _reloadCurrentForMixChange();
    }
  }

  // ── Media session command bridge ──────────────────────────

  void _onMediaSessionCommand(MediaSessionCommand cmd) {
    switch (cmd.action) {
      case 'play':
      case 'pause':
      case 'toggle':
        unawaited(_playerService.playPause());
        break;
      case 'stop':
        unawaited(_playerService.stop());
        break;
      case 'next':
        unawaited(_advancePlaylist(1));
        break;
      case 'previous':
        unawaited(_advancePlaylist(-1));
        break;
      case 'seek':
        if (cmd.positionMs != null) {
          unawaited(_playerService.seek(Duration(milliseconds: cmd.positionMs!)));
        }
        break;
    }
  }

  // ── Resume position ─────────────────────────────────

  void _persistResumePosition() {
    if (!_settings.resumePlaybackEnabled) return;
    final path = _resumePathInProgress;
    if (path == null) return;
    final pos = _position;
    final dur = _duration;
    if (pos.inSeconds < SettingsService.resumeMinElapsedSeconds) return;
    if (dur.inSeconds > 0 &&
        (dur - pos).inSeconds < SettingsService.resumeTailIgnoreSeconds) {
      _settings.saveResumePosition(path, null);
      return;
    }
    _settings.saveResumePosition(path, pos.inMilliseconds);
  }

  Future<void> _maybeApplyResume(String path) async {
    final ms = _settings.resumePositionFor(path);
    if (ms == null || ms <= 0) return;
    // Wait briefly until duration is known so we don't seek beyond end.
    for (var i = 0; i < 20; i++) {
      if (_duration.inMilliseconds > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_isDisposed || _currentFile != path) return;
    }
    if (_duration.inMilliseconds > 0 &&
        ms >= _duration.inMilliseconds -
            SettingsService.resumeTailIgnoreSeconds * 1000) {
      _settings.saveResumePosition(path, null);
      return;
    }
    try {
      await _playerService.seek(Duration(milliseconds: ms));
      if (mounted) {
        _showOsdMessage('Resumed at ${_formatHms(Duration(milliseconds: ms))}');
      }
    } catch (_) {}
  }

  static String _formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes.remainder(60)}:$s';
  }

  // ── Playlist ────────────────────────────────────────

  Future<void> _advancePlaylist(int delta, {bool fromCompletion = false}) async {
    if (_playlist.isEmpty) return;
    final next = _playlist.advance(delta);
    if (next == null) return;
    _showOsdMessage(delta > 0 ? 'Next in queue' : 'Previous in queue');
    await _loadFile(next);
  }

  void _enqueue(List<String> paths, {bool playNow = false}) {
    if (paths.isEmpty) return;
    if (playNow || _playlist.isEmpty) {
      _playlist.replace(paths);
      final first = _playlist.current;
      if (first != null) unawaited(_loadFile(first));
    } else {
      _playlist.addAll(paths);
      _showOsdMessage(
        paths.length == 1 ? 'Added to queue' : 'Added ${paths.length} to queue',
      );
    }
  }

  // ── Compact / mini-player mode ────────────────────────────

  Future<void> _toggleCompactMode() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
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
      } catch (_) {}
      setState(() => _compactMode = false);
      _showOsdMessage('Mini-player off');
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
      } catch (_) {}
      setState(() => _compactMode = true);
      _showOsdMessage('Mini-player on');
    }
  }

  // ── More menu ─────────────────────────────────────────────

  void _showMoreMenu() async {
    final tracks = _currentTracks;
    final hasAudioOptions = tracks != null && tracks.audio.length > 1;
    final hasSubOptions = tracks != null && tracks.subtitle.isNotEmpty;
    if (_chapters.isEmpty) await _refreshChapters();
    if (!mounted) return;
    final hasChapters = _chapters.isNotEmpty;

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.20),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final experimentalAmber = Color.lerp(cs.tertiary, Colors.amber, 0.72)!;
        final experimentalBackground = Color.alphaBlend(
          experimentalAmber.withValues(alpha: isDark ? 0.16 : 0.11),
          cs.surface,
        );
        final experimentalBorder =
            experimentalAmber.withValues(alpha: isDark ? 0.45 : 0.36);
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: cs.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 13),
                    ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: experimental ? experimentalIcon : cs.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                    ),
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
                              label: 'Audio track',
                              action: 'audio',
                            ),
                          if (hasSubOptions)
                            item(
                              icon: Icons.subtitles,
                              label: 'Subtitle track',
                              action: 'subtitle',
                            ),
                          if (hasChapters)
                            item(
                              icon: Icons.menu_book,
                              label: 'Chapters',
                              action: 'chapters',
                            ),
                          item(
                            icon: Icons.graphic_eq,
                            label: 'Equalizer',
                            action: 'equalizer',
                          ),
                          if (_currentFile != null && !_isAudioFile)
                            item(
                              icon: Icons.photo_camera,
                              label: 'Take screenshot',
                              action: 'screenshot',
                            ),
                          if (hasAudioOptions &&
                              _settings.experimentalFeaturesEnabled)
                            switchItem(
                              icon: Icons.multitrack_audio,
                              label: 'Mix all audio tracks',
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
                          if (!_isAudioFile)
                            switchItem(
                              icon: Icons.image_search,
                              label: 'Seek thumbnails (beta: uses more resources)',
                              value: _settings.seekPreviewEnabled,
                              onChanged: (v) {
                                _settings.seekPreviewEnabled = v;
                                setSheetState(() {});
                                unawaited(
                                  _seekPreviewService.setEnabled(v).then((_) {
                                    if (v && _currentFile != null) {
                                      return _seekPreviewService
                                          .setSource(_currentFile);
                                    }
                                    return null;
                                  }),
                                );
                                if (mounted) setState(() {});
                              },
                            ),
                          item(
                            icon: Icons.keyboard,
                            label: 'Keyboard shortcuts',
                            action: 'keybinds',
                          ),
                          const Divider(height: 1),
                          item(
                            icon: Icons.queue_music,
                            label: _playlist.isEmpty
                                ? 'Queue (empty)'
                                : 'Queue (${_playlist.length})',
                            action: 'queue',
                          ),
                          item(
                            icon: Icons.playlist_add,
                            label: 'Add files to queue…',
                            action: 'enqueue',
                          ),
                          switchItem(
                            icon: Icons.shuffle,
                            label: 'Shuffle queue',
                            value: _settings.playlistShuffle,
                            onChanged: (v) {
                              _settings.playlistShuffle = v;
                              _playlist.setShuffle(v);
                              setSheetState(() {});
                            },
                          ),
                          switchItem(
                            icon: Icons.picture_in_picture_alt,
                            label: 'Mini-player (always on top)',
                            value: _compactMode,
                            onChanged: (_) =>
                                Navigator.pop(ctx, 'compact'),
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
      case 'mix':
        unawaited(_applyMultiAudioMix());
        break;
      case 'keybinds':
        unawaited(_showKeybindsDialog());
        break;
      case 'queue':
        unawaited(_showQueueDialog());
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
    final tracks = _currentTracks;
    if (tracks == null) return;
    final list = tracks.audio
        .where((t) => t.id != 'auto')
        .toList(growable: false);
    final current = _currentTrackSelection?.audio.id;
    final selected = await showDialog<AudioTrack>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Audio track'),
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
    final tracks = _currentTracks;
    if (tracks == null) return;
    final list = [
      SubtitleTrack.no(),
      ...tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    final current = _currentTrackSelection?.subtitle.id;
    final selected = await showDialog<SubtitleTrack>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Subtitle track'),
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
                            ? 'Off'
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
      _subtitlesVisible = selected.id != 'no';
    }
  }

  Future<void> _showChaptersDialog() async {
    if (_chapters.isEmpty) await _refreshChapters();
    if (!mounted || _chapters.isEmpty) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chapters'),
        children: _chapters
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.index),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        _formatDuration(c.time),
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
            final bands = List<double>.from(_settings.eqBands);
            return AlertDialog(
              title: const Text('Equalizer'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('Enable'),
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
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.label),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(SettingsService.eqBandCount, (i) {
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
                                Text(label,
                                    style: Theme.of(ctx).textTheme.bodySmall),
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
                        SettingsService.eqBandCount, 0);
                    _settings.eqPreset = 'flat';
                    unawaited(_applyEqualizer());
                    setLocal(() {});
                  },
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
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
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
      );
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

  Future<void> _showQueueDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final items = _playlist.items;
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Play queue')),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        _playlist.clear();
                        setLocal(() {});
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 360,
                child: items.isEmpty
                    ? const Center(child: Text('Queue is empty.'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (c, i) {
                          final isCurrent = i == _playlist.index;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isCurrent ? Icons.play_arrow : Icons.music_note,
                              size: 18,
                            ),
                            title: Text(
                              p.basename(items[i]),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            onTap: () {
                              _playlist.jumpTo(i);
                              unawaited(_loadFile(items[i]));
                              Navigator.pop(ctx);
                            },
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _playlist.removeAt(i);
                                setLocal(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _pickFilesToEnqueue();
                  },
                  child: const Text('Add files\u2026'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showKeybindsDialog() async {
    final current = Map<String, List<String>>.from(_settings.keybinds);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Keyboard shortcuts'),
            content: SizedBox(
              width: 460,
              height: 480,
              child: Scrollbar(
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        'Tip: press F1 or ? at any time to reopen this dialog.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    ...PlayerShortcutAction.values.map((a) {
                    final accels = current[a.name] ??
                        defaultKeybinds[a]?.toList(growable: true) ??
                        const <String>[];
                    return ListTile(
                      dense: true,
                      title: Text(shortcutActionLabel(a)),
                      subtitle: Text(
                        accels.isEmpty ? '(none)' : accels.join(', '),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Set new binding',
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
                            tooltip: 'Reset to default',
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
                child: const Text('Reset all'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<String?> _captureKeybind(BuildContext context) async {
    final node = FocusNode();
    String? captured;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Press a key combination'),
          content: SizedBox(
            width: 320,
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
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: captured == null ? null : () => Navigator.pop(ctx),
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
    node.dispose();
    return captured;
  }
}

class _ChapterInfo {
  const _ChapterInfo({
    required this.index,
    required this.title,
    required this.time,
  });
  final int index;
  final String title;
  final Duration time;
}

class _CompactExitButton extends StatefulWidget {
  const _CompactExitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CompactExitButton> createState() => _CompactExitButtonState();
}

class _CompactExitButtonState extends State<_CompactExitButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Exit mini-player',
      child: Semantics(
        button: true,
        label: 'Exit mini-player',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: _hovering ? 0.72 : 0.48,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: _hovering ? 0.85 : 0.55,
                  ),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close_fullscreen,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
