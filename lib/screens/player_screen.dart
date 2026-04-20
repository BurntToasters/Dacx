import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../services/player_service.dart';
import '../services/settings_service.dart';
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
  final String? initialFile;

  const PlayerScreen({super.key, required this.settings, this.initialFile});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerService _playerService;
  late final VideoController _videoController;
  final UpdateService _updateService = UpdateService();

  SettingsService get _settings => widget.settings;

  String? _currentFile;
  bool _isDragging = false;
  bool _isAudioFile = false;
  bool _hasVideoOutput = false;

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

  @override
  void initState() {
    super.initState();
    _playerService = PlayerService();
    final hwDec = _settings.hwDec;
    _videoController = VideoController(
      _playerService.player,
      configuration: VideoControllerConfiguration(
        hwdec: hwDec,
        enableHardwareAcceleration: _shouldEnableHardwareAcceleration(hwDec),
      ),
    );
    _volume = _settings.volume;

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
      }),
      _playerService.playingStream.listen((playing) {
        setState(() => _isPlaying = playing);
      }),
      _playerService.volumeStream.listen((vol) {
        setState(() => _volume = vol);
      }),
      _playerService.player.stream.width.listen((w) {
        final has = w != null && w > 0;
        if (has != _hasVideoOutput) {
          setState(() => _hasVideoOutput = has);
        }
      }),
      _playerService.completedStream.listen((completed) {
        if (completed && mounted) {
          setState(() => _position = Duration.zero);
        }
      }),
    ]);

    // Listen for settings changes (speed, loop, always-on-top).
    _settings.addListener(_onSettingsChanged);
    _initializePlatformFileOpenBridge();

    _checkForUpdates();

    // Auto-open CLI file.
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openRequestedFile(widget.initialFile!));
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _playerService.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _applySpeed(_settings.speed);
    _applyLoopMode(_settings.loopMode);
    windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
    if (mounted) {
      setState(() {});
    }
  }

  void _initializePlatformFileOpenBridge() {
    if (!Platform.isMacOS) return;
    unawaited(_bootstrapMacOpenFileBridge());
  }

  Future<void> _bootstrapMacOpenFileBridge() async {
    try {
      final pending = await _macOpenFileMethodChannel.invokeListMethod<dynamic>(
        'getPendingFiles',
      );
      if (pending != null && pending.isNotEmpty) {
        for (final entry in pending) {
          final path = _coerceOpenPath(entry);
          if (path == null) continue;
          await _openRequestedFile(path);
        }
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      // Ignore if the native bridge is unavailable.
      return;
    } catch (_) {}

    _subscriptions.add(
      _macOpenFileEventChannel.receiveBroadcastStream().listen((event) {
        final path = _coerceOpenPath(event);
        if (path != null) {
          unawaited(_openRequestedFile(path));
        }
      }, onError: (_) {}),
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
    if (_currentFile == trimmed) return;
    await _loadFile(trimmed);
  }

  void _applySpeed(double speed) {
    _playerService.setRate(speed);
  }

  bool _shouldEnableHardwareAcceleration(String hwDec) {
    if (hwDec == 'no' || hwDec == 'auto-safe') return false;
    if ((Platform.isMacOS || Platform.isLinux) && kDebugMode) return false;
    return true;
  }

  void _applyHwDec(String value) {
    try {
      final nativePlayer = _playerService.player.platform;
      if (nativePlayer is NativePlayer) {
        nativePlayer.setProperty('hwdec', value);
      }
    } catch (_) {
      // hwdec may not be available on all platforms.
    }
  }

  void _applyLoopMode(LoopMode mode) {
    final plMode = switch (mode) {
      LoopMode.none => PlaylistMode.none,
      LoopMode.single => PlaylistMode.single,
      LoopMode.loop => PlaylistMode.loop,
    };
    _playerService.setPlaylistMode(plMode);
  }

  // ── Update check with cooldown ────────────────────────────

  Future<void> _checkForUpdates() async {
    if (!_settings.shouldCheckForUpdate) return;
    final update = await _updateService.checkForUpdate();
    _settings.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
    if (update != null && mounted) {
      _showUpdateSnackbar(update);
    }
  }

  void _showUpdateSnackbar(UpdateInfo update) {
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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        lockParentWindow: true,
        allowMultiple: false,
      );

      if (result == null) return;
      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read selected file path.')),
          );
        }
        return;
      }

      await _loadFile(path);
    } on PlatformException catch (e) {
      if (mounted) {
        final detail = e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : e.code;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File picker failed: $detail')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open file picker.')),
        );
      }
    }
  }

  Future<void> _loadFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    if (!_supportedExtensions.contains(ext)) {
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
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    _settings.addRecentFile(filePath);

    try {
      await _playerService.open(filePath, play: _settings.autoPlay);
    } catch (e) {
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
      _loadFile(details.files.first.path);
    }
  }

  void _loadRecentFile(String path) => _loadFile(path);

  // ── Navigation ────────────────────────────────────────────

  void _openSettings() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => SettingsScreen(settings: _settings),
        opaque: false,
        transitionsBuilder: (context, animation, _, child) {
          // Mask ramps up quickly to hide the player underneath the
          // semi-transparent settings scaffold when blur is active.
          final maskOpacity = Curves.easeOut
              .transform((animation.value / 0.45).clamp(0.0, 1.0));
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
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: maskOpacity),
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
      _openFile();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      if (_currentFile != null) {
        _playerService.playPause();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(const Duration(seconds: 5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(const Duration(seconds: -5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyM) {
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
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _playerService.setVolume(newVol);
    _settings.volume = newVol;
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _playerService.setVolume(0);
      _settings.volume = 0;
    } else {
      _playerService.setVolume(_volumeBeforeMute);
      _settings.volume = _volumeBeforeMute;
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Column(
          children: [
            const CustomTitleBar(),
            Expanded(
              child: DropTarget(
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
                onDragDone: _onDragDone,
                child: Column(
                  children: [
                    // Video / Audio art / Drop zone
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
                                  ?currentChild,
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
                              child: Container(
                                color: Colors.blue.withValues(alpha: 0.3),
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
                    // Seek bar
                    AnimatedSize(
                      duration: const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _duration.inMilliseconds > 0
                          ? Padding(
                              key: const ValueKey('seek-visible'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _position.inMilliseconds
                                          .toDouble()
                                          .clamp(
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
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('seek-hidden'),
                              width: double.infinity,
                            ),
                    ),
                    // Transport controls
                    TransportControls(
                      isPlaying: _isPlaying,
                      volume: _volume,
                      hasMedia: _currentFile != null,
                      speed: _settings.speed,
                      loopMode: _settings.loopMode,
                      recentFiles: _settings.recentFiles,
                      onPlayPause: () async {
                        try {
                          await _playerService.playPause();
                        } catch (_) {}
                      },
                      onStop: () async {
                        await _playerService.stop();
                        setState(() {
                          _currentFile = null;
                          _isAudioFile = false;
                          _hasVideoOutput = false;
                          _position = Duration.zero;
                          _duration = Duration.zero;
                        });
                      },
                      onOpenFile: _openFile,
                      onVolumeChanged: (vol) async {
                        try {
                          await _playerService.setVolume(vol);
                          _settings.volume = vol;
                        } catch (_) {}
                      },
                      onLoopModeChanged: (mode) {
                        _settings.loopMode = mode;
                      },
                      onRecentFileSelected: _loadRecentFile,
                      onSettingsPressed: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropZone() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Drop a file here or click Open',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
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

  Widget _buildMediaSurface() {
    if (_currentFile == null) {
      return KeyedSubtree(
        key: const ValueKey('media-drop-zone'),
        child: _buildDropZone(),
      );
    }

    if (!_isAudioFile || _hasVideoOutput) {
      return Container(
        key: const ValueKey('media-video'),
        color: Colors.black,
        child: Video(controller: _videoController, controls: NoVideoControls),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('media-audio'),
      child: _buildAudioBackground(),
    );
  }

  Widget _buildAudioBackground() {
    final fileName = _currentFile != null
        ? p.basenameWithoutExtension(_currentFile!)
        : '';
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.surface, colorScheme.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album,
              size: 128,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                fileName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


