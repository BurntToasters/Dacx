import 'dart:async';

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
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/transport_controls.dart';
import 'settings_screen.dart';

const _audioExtensions = {
  'mp3', 'flac', 'wav', 'ogg', 'aac', 'm4a', 'wma', 'opus', 'ape', 'alac',
};

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
    'mp4', 'mkv', 'avi', 'webm', 'mov', 'wmv', 'flv', 'm4v',
  };

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _playerService = PlayerService();
    _videoController = VideoController(_playerService.player);
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

    _checkForUpdates();

    // Auto-open CLI file.
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFile(widget.initialFile!);
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
  }

  void _applySpeed(double speed) {
    _playerService.setRate(speed);
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
        content: Text('DACX v${update.version} is available'),
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3', 'flac', 'wav', 'ogg', 'aac', 'm4a', 'wma', 'opus',
        'mp4', 'mkv', 'avi', 'webm', 'mov', 'wmv', 'flv', 'm4v',
      ],
    );

    if (result != null && result.files.single.path != null) {
      _loadFile(result.files.single.path!);
    }
  }

  Future<void> _loadFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    if (!_supportedExtensions.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unsupported file type: .$ext')),
        );
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
        setState(() { _currentFile = null; _isAudioFile = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $e')),
        );
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
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: _settings),
      ),
    );
  }

  // ── Keyboard shortcuts ────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

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
                    if (_currentFile == null)
                      _buildDropZone()
                    else if (!_isAudioFile || _hasVideoOutput)
                      Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                      )
                    else
                      _buildAudioBackground(),
                    if (_isDragging)
                      Container(
                        color: Colors.blue.withValues(alpha: 0.3),
                        child: const Center(
                          child: Icon(Icons.file_download, size: 64, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              // Seek bar
              if (_duration.inMilliseconds > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                              _position = Duration(milliseconds: value.toInt());
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
                  try { await _playerService.playPause(); } catch (_) {}
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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

  Widget _buildAudioBackground() {
    final fileName = _currentFile != null ? p.basenameWithoutExtension(_currentFile!) : '';
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerHighest,
          ],
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
