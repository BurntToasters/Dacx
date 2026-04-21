import 'dart:async';
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
import '../services/settings_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/debug_log_service.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
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

  SettingsService get _settings => widget.settings;

  String? _currentFile;
  bool _isDragging = false;
  bool _isAudioFile = false;
  bool _hasVideoOutput = false;
  bool _hasAlbumArtTrack = false;

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
    _playerService.setVolume(_volume);
    _applySpeed(_settings.speed);
    _applyLoopMode(_settings.loopMode);
    _applyHwDec(_settings.hwDec);

    _subscriptions.addAll([
      _playerService.positionStream.listen((pos) {
        if (!_isSeeking) setState(() => _position = pos);
      }),
      _playerService.durationStream.listen((dur) {
        setState(() => _duration = dur);
        if (dur.inMilliseconds > 0 && widget.debugLog.isEnabled) {
          _log(
            'duration_updated',
            detailsBuilder: () => {'duration_ms': dur.inMilliseconds},
          );
        }
      }),
      _playerService.playingStream.listen((playing) {
        setState(() => _isPlaying = playing);
        if (widget.debugLog.isEnabled) {
          _log(
            'playing_state_changed',
            detailsBuilder: () => {'playing': playing},
          );
        }
      }),
      _playerService.volumeStream.listen((vol) {
        setState(() => _volume = vol);
        if (widget.debugLog.isEnabled) {
          _log(
            'volume_stream_updated',
            detailsBuilder: () => {'volume': vol.toStringAsFixed(2)},
          );
        }
      }),
      _playerService.player.stream.width.listen((w) {
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
        final hasAlbumArt = _hasEmbeddedAlbumArtTrack(tracks);
        if (hasAlbumArt != _hasAlbumArtTrack) {
          setState(() => _hasAlbumArtTrack = hasAlbumArt);
          if (widget.debugLog.isEnabled) {
            _log(
              'album_art_track_changed',
              detailsBuilder: () => {'has_album_art_track': hasAlbumArt},
            );
          }
        }
      }),
      _playerService.completedStream.listen((completed) {
        if (completed && mounted) {
          setState(() => _position = Duration.zero);
          if (widget.debugLog.isEnabled) {
            _log('playback_completed');
          }
        }
      }),
    ]);

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
    _log('player_dispose');
    _settings.removeListener(_onSettingsChanged);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _playerService.dispose();
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
    windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
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
    try {
      final pending = await _macOpenFileMethodChannel.invokeListMethod<dynamic>(
        'getPendingFiles',
      );
      if (pending != null && pending.isNotEmpty) {
        _log(
          'mac_pending_files_found',
          category: DebugLogCategory.system,
          detailsBuilder: () => {'count': pending.length},
        );
        for (final entry in pending) {
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

    _subscriptions.add(
      _macOpenFileEventChannel.receiveBroadcastStream().listen(
        (event) {
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
    _playerService.setRate(speed);
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
    _playerService.setPlaylistMode(plMode);
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        lockParentWindow: true,
        allowMultiple: false,
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
        ).showSnackBar(SnackBar(content: Text('File picker failed: $detail')));
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

  Future<void> _loadFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    _log(
      'file_load_started',
      detailsBuilder: () => {'path': filePath, 'extension': ext},
    );
    if (!_supportedExtensions.contains(ext)) {
      _log(
        'file_load_unsupported_extension',
        detailsBuilder: () => {'extension': ext, 'path': filePath},
        severity: DebugSeverity.warn,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unsupported file type: .$ext')));
      }
      return;
    }
    final gen = ++_loadGen;
    setState(() {
      _currentFile = filePath;
      _isAudioFile = _audioExtensions.contains(ext);
      _hasVideoOutput = false;
      _hasAlbumArtTrack = false;
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

    _settings.addRecentFile(filePath);
    _log(
      'recent_file_added',
      category: DebugLogCategory.settings,
      detailsBuilder: () => {'path': filePath},
    );

    try {
      await _playerService.open(filePath, play: _settings.autoPlay);
      _log(
        'file_load_succeeded',
        detailsBuilder: () => {
          'path': filePath,
          'auto_play': _settings.autoPlay,
        },
      );
    } catch (e) {
      _log(
        'file_load_failed',
        message: e.toString(),
        detailsBuilder: () => {'path': filePath},
        severity: DebugSeverity.error,
      );
      if (gen != _loadGen) return;
      if (mounted) {
        setState(() {
          _currentFile = null;
          _isAudioFile = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open file: $e')));
      }
    }
  }

  void _onDragDone(DropDoneDetails details) {
    if (details.files.isNotEmpty) {
      _log(
        'drop_file_received',
        detailsBuilder: () => {
          'path': details.files.first.path,
          'count': details.files.length,
        },
      );
      _loadFile(details.files.first.path);
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
    _log('recent_file_open_requested', detailsBuilder: () => {'path': path});
    _loadFile(path);
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
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final hk = HardwareKeyboard.instance;

    if (event is KeyDownEvent &&
        (hk.isMetaPressed || hk.isControlPressed) &&
        key == LogicalKeyboardKey.keyO) {
      _log('shortcut_open_file', category: DebugLogCategory.ui);
      _openFile();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      if (_currentFile != null) {
        _playerService.playPause();
        _log('shortcut_play_pause', category: DebugLogCategory.ui);
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _log('shortcut_seek_forward', category: DebugLogCategory.ui);
      _seekRelative(const Duration(seconds: 5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _log('shortcut_seek_back', category: DebugLogCategory.ui);
      _seekRelative(const Duration(seconds: -5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _log('shortcut_volume_up', category: DebugLogCategory.ui);
      _adjustVolume(5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _log('shortcut_volume_down', category: DebugLogCategory.ui);
      _adjustVolume(-5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyM) {
      _log('shortcut_toggle_mute', category: DebugLogCategory.ui);
      _toggleMute();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double _volumeBeforeMute = 100.0;

  void _seekRelative(Duration offset) {
    if (_duration.inMilliseconds == 0) return;
    var target = _position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
    _playerService.seek(target);
    _log(
      'seek_relative',
      detailsBuilder: () => {'target_ms': target.inMilliseconds},
    );
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _playerService.setVolume(newVol);
    _settings.volume = newVol;
    _log(
      'volume_adjusted',
      detailsBuilder: () => {'volume': newVol.toStringAsFixed(2)},
    );
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _playerService.setVolume(0);
      _settings.volume = 0;
      _log(
        'mute_enabled',
        detailsBuilder: () => {'previous_volume': _volumeBeforeMute},
      );
    } else {
      _playerService.setVolume(_volumeBeforeMute);
      _settings.volume = _volumeBeforeMute;
      _log(
        'mute_disabled',
        detailsBuilder: () => {'restored_volume': _volumeBeforeMute},
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
                              child: _buildMediaSurface(),
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
                          child: Slider(
                            value: _position.inMilliseconds.toDouble().clamp(
                              0.0,
                              _duration.inMilliseconds.toDouble(),
                            ),
                            max: _duration.inMilliseconds.toDouble(),
                            onChangeStart: (_) => _isSeeking = true,
                            onChanged: (value) {
                              setState(() {
                                _position = Duration(
                                  milliseconds: value.toInt(),
                                );
                              });
                            },
                            onChangeEnd: (value) {
                              _isSeeking = false;
                              _playerService.seek(
                                Duration(milliseconds: value.toInt()),
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
              setState(() {
                _currentFile = null;
                _isAudioFile = false;
                _hasVideoOutput = false;
                _hasAlbumArtTrack = false;
                _position = Duration.zero;
                _duration = Duration.zero;
              });
            },
            onOpenFile: _openFile,
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
          FilledButton.icon(
            onPressed: _openFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open File'),
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
          padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
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
      final showAlbumArt = _hasAlbumArtTrack && _hasVideoOutput;
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
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final albumArtSize = shortestSide.clamp(220.0, 360.0).toDouble();

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
          Text(
            fileName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.88),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text(
            'Audio playback',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
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

  bool _hasEmbeddedAlbumArtTrack(Tracks tracks) {
    return tracks.video.any((track) {
      final id = track.id.toLowerCase();
      if (id == 'auto' || id == 'no') return false;
      return track.albumart == true || track.image == true;
    });
  }
}
