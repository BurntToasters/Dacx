import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../../models/playable_source.dart';
import '../../playback/linux_install_kind.dart';
import '../../playback/media_session_command_dispatch.dart';
import '../../playback/playback_controller.dart';
import '../../playback/player_controller.dart';
import '../../playback/subscription_bag.dart';
import '../../services/app_exit_hooks.dart';
import '../../services/debug_log_service.dart';
import '../../services/idle_inhibit_service.dart';
import '../../services/media_session_service.dart';
import '../../services/player_service.dart';
import '../../services/settings_service.dart';
import '../../services/windows_shell_service.dart';

typedef MediaSessionLog = void Function(
  String event, {
  DebugLogCategory category,
  String? message,
  DebugSeverity severity,
});

class MediaSessionCoordinator {
  MediaSessionCoordinator({
    required this.settings,
    required this.playerService,
    required this.mediaSession,
    required this.idleInhibit,
    required this.player,
    required this.playback,
    required this.log,
    required this.isMounted,
    required this.isDisposed,
    required this.update,
    required this.onStop,
    required this.onAdvancePlaylist,
    required this.onSetShuffle,
    required this.onQuitRequest,
  });

  final SettingsService settings;
  final IPlayerService playerService;
  final MediaSessionService mediaSession;
  final IdleInhibitService idleInhibit;
  final PlayerController player;
  final PlaybackController playback;
  final MediaSessionLog log;
  final bool Function() isMounted;
  final bool Function() isDisposed;
  final void Function(VoidCallback fn) update;
  final Future<void> Function() onStop;
  final Future<void> Function(int delta) onAdvancePlaylist;
  final void Function(bool on) onSetShuffle;
  final Future<void> Function()? Function() onQuitRequest;

  String? _displayTitle;
  String? _displayArtist;
  int _artExportGen = 0;
  String? _lastArtUri;
  DateTime? _lastTaskbarProgressAt;

  String? get displayTitle => _displayTitle;
  String? get displayArtist => _displayArtist;

  void init() {
    unawaited(
      mediaSession.init(enabled: settings.mediaSessionEnabled).catchError((
        Object e,
      ) {
        log(
          'media_session_init_failed',
          category: DebugLogCategory.system,
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }),
    );
  }

  void attachCommands(
    SubscriptionBag subscriptions, {
    Stream<MediaSessionCommand>? testCommands,
  }) {
    subscriptions.add(mediaSession.commands.listen(onCommand));
    if (testCommands != null) {
      subscriptions.add(testCommands.listen(onCommand));
    }
  }

  void clearDisplayMetadata() {
    _displayTitle = null;
    _displayArtist = null;
  }

  void resetArtForNewLoad() {
    _artExportGen++;
    _lastArtUri = null;
  }

  void onPosition(Duration pos) {
    if (settings.mediaSessionEnabled) {
      _maybeUpdatePosition(pos);
    }
    _maybeUpdateTaskbarProgress(pos);
  }

  void onDuration(Duration dur) {
    if (dur.inMilliseconds > 0 && settings.mediaSessionEnabled) {
      final source = player.currentSource;
      if (source != null) {
        unawaited(refreshMetadata(source, duration: dur, exportArt: false));
      }
    }
  }

  void onPlayingChanged(bool playing) {
    syncIdleInhibit();
    if (!playing) {
      unawaited(WindowsShellService.clearTaskbarProgress());
    }
    if (settings.mediaSessionEnabled) {
      _maybeUpdatePosition(player.position);
    }
  }

  void updateVolume(double volume) {
    unawaited(mediaSession.updateVolume((volume / 100.0).clamp(0.0, 1.0)));
  }

  void updateRate(double rate) {
    unawaited(mediaSession.updateRate(rate));
  }

  void updateLoopMode(LoopMode mode) {
    unawaited(
      mediaSession.updateLoop(switch (mode) {
        LoopMode.none => 'none',
        LoopMode.single => 'single',
        LoopMode.loop => 'loop',
      }),
    );
  }

  void updateShuffle(bool on) {
    unawaited(mediaSession.updateShuffle(on));
  }

  void setEnabled(bool enabled) {
    unawaited(mediaSession.setEnabled(enabled));
  }

  void clearSession() {
    unawaited(mediaSession.clear());
  }

  void syncIdleInhibit() {
    unawaited(
      idleInhibit.setPlaying(player.isPlaying, hasVideo: !player.isAudioFile),
    );
  }

  void dispose() {
    unawaited(mediaSession.dispose());
    unawaited(idleInhibit.dispose());
  }

  Future<void> refreshMetadata(
    PlayableSource source, {
    Duration? duration,
    bool exportArt = true,
    int? gen,
  }) async {
    if (isDisposed()) return;
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final pushToSession = settings.mediaSessionEnabled;
    String? artist;
    String? album;
    String? metaTitle;
    try {
      artist = await playerService.getProperty('metadata/by-key/artist');
      if (pushToSession) {
        album = await playerService.getProperty('metadata/by-key/album');
      }
      metaTitle = await playerService.getProperty('metadata/by-key/title');
    } catch (_) {
      // Metadata is best-effort; title falls back to display name.
    }
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    final title = (metaTitle != null && metaTitle.trim().isNotEmpty)
        ? metaTitle.trim()
        : source.displayName;
    final artistName = (artist != null && artist.trim().isNotEmpty)
        ? artist.trim()
        : null;
    if (isMounted()) {
      update(() {
        _displayTitle = title;
        _displayArtist = artistName;
      });
    }
    if (!pushToSession || !settings.mediaSessionEnabled) return;
    String? artUri;
    if (exportArt && player.hasAlbumArtTrack) {
      artUri = await _exportAlbumArt();
    } else if (!exportArt) {
      artUri = _lastArtUri;
    }
    if (gen != null && !playback.isLoadCurrent(gen)) return;
    await mediaSession.updateMetadata(
      title: title,
      artist: artistName,
      album: (album != null && album.trim().isNotEmpty) ? album.trim() : null,
      duration: duration ?? player.duration,
      artUri: artUri,
      trackIdentity: '${source.value}#${playback.loadGeneration}',
    );
  }

  Future<String?> _exportAlbumArt() async {
    final exportGen = ++_artExportGen;
    try {
      final bytes = await playerService.screenshot(format: 'image/jpeg');
      if (exportGen != _artExportGen) return null;
      if (bytes == null || bytes.isEmpty) return null;
      final dir = _artDirectory();
      await dir.create(recursive: true);
      if (exportGen != _artExportGen) return null;
      // Prefix with the pid so instances never share or delete each other's art.
      final prefix = 'artwork-$pid-';
      final file = File(p.join(dir.path, '$prefix$exportGen.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      if (exportGen != _artExportGen) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup for an obsolete artwork export.
        }
        return null;
      }
      final uri = file.uri.toString();
      _lastArtUri = uri;
      // Own older exports go now; other instances' files only once stale, so
      // art left by a crashed instance does not pile up.
      final staleBefore = DateTime.now().subtract(const Duration(days: 1));
      final entries = await dir.list().toList();
      for (final candidate in entries.whereType<File>()) {
        if (candidate.path == file.path) continue;
        final name = p.basename(candidate.path);
        if (!name.startsWith('artwork-') || !name.endsWith('.jpg')) {
          continue;
        }
        if (name.startsWith(prefix)) {
          final ownGen = int.tryParse(
            name.substring(prefix.length, name.length - '.jpg'.length),
          );
          if (ownGen != null && ownGen > exportGen) continue;
        } else {
          try {
            final stat = await FileStat.stat(candidate.path);
            if (stat.type == FileSystemEntityType.notFound ||
                !stat.modified.isBefore(staleBefore)) {
              continue;
            }
          } catch (_) {
            continue;
          }
        }
        try {
          await candidate.delete();
        } catch (_) {
          // Artwork cleanup is best-effort.
        }
      }
      return uri;
    } catch (e) {
      log(
        'media_session_art_export_failed',
        message: e.toString(),
        severity: DebugSeverity.warn,
      );
      return null;
    }
  }

  Directory _artDirectory() {
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

  void _maybeUpdatePosition(Duration pos) {
    if (!playback.mediaSessionThrottle.shouldSend(DateTime.now())) {
      return;
    }
    unawaited(mediaSession.updatePosition(pos, playing: player.isPlaying));
  }

  void _maybeUpdateTaskbarProgress(Duration pos) {
    if (!Platform.isWindows || !player.isPlaying) return;
    final dur = player.duration;
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

  Future<void> syncJumpList() async {
    if (!Platform.isWindows) return;
    await WindowsShellService.updateJumpList(settings.recentFiles);
  }

  void clearJumpList() {
    if (Platform.isWindows) {
      unawaited(WindowsShellService.updateJumpList(const []));
    }
  }

  void rememberRecentAndJumpList(String path) {
    settings.addRecentFile(path);
    unawaited(syncJumpList());
  }

  void _deferSetting(void Function() apply) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() || isDisposed()) return;
      apply();
    });
  }

  void onCommand(MediaSessionCommand cmd) {
    final dispatch = MediaSessionCommandDispatch.resolve(
      cmd,
      position: player.position,
      duration: player.duration,
    );
    switch (dispatch.kind) {
      case MediaSessionDispatchKind.play:
        unawaited(playerService.play());
      case MediaSessionDispatchKind.pause:
        unawaited(playerService.pause());
      case MediaSessionDispatchKind.toggle:
        unawaited(playerService.playPause());
      case MediaSessionDispatchKind.stop:
        unawaited(onStop());
      case MediaSessionDispatchKind.next:
        unawaited(onAdvancePlaylist(1));
      case MediaSessionDispatchKind.previous:
        unawaited(onAdvancePlaylist(-1));
      case MediaSessionDispatchKind.seek:
        final target = dispatch.seekTarget;
        if (target != null) {
          unawaited(playerService.seek(target));
        }
      case MediaSessionDispatchKind.setLoopMode:
        final mode = dispatch.loopMode;
        if (mode != null) {
          _deferSetting(() => settings.loopMode = mode);
        }
      case MediaSessionDispatchKind.setShuffle:
        final on = dispatch.shuffle;
        if (on != null) {
          _deferSetting(() => onSetShuffle(on));
        }
      case MediaSessionDispatchKind.setVolume:
        final pct = dispatch.volumePercent;
        if (pct != null) {
          _deferSetting(() {
            update(() {
              player.volume = pct;
            });
            settings.volume = pct;
            unawaited(playerService.setVolume(pct).catchError((_) {}));
          });
        }
      case MediaSessionDispatchKind.setRate:
        final rate = dispatch.rate;
        if (rate != null) {
          _deferSetting(() => settings.speed = rate);
        }
      case MediaSessionDispatchKind.raise:
        unawaited(windowManager.show().catchError((_) {}));
        unawaited(windowManager.focus().catchError((_) {}));
      case MediaSessionDispatchKind.quit:
        final onQuit = onQuitRequest();
        if (onQuit != null) {
          unawaited(onQuit());
        } else {
          unawaited(() async {
            await AppExitHooks.runAll();
            if (isDisposed()) return;
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
}
