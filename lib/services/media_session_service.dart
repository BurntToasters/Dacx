import 'dart:async';
import 'dart:io';

import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:flutter/services.dart';

import 'debug_log_service.dart';

/// Cross-platform media-session bridge.
///
/// On Linux this uses [MPRISService] (pure-Dart D-Bus) directly. On Windows
/// and macOS a [MethodChannel] forwards to native handlers in the runners
/// (C++/WinRT SMTC on Windows, Swift `MPNowPlayingInfoCenter` on macOS).
/// When the platform-side handler isn't registered, all calls degrade to
/// no-ops with a single debug log.
///
/// Channel: `run.rosie.dacx/media_session`
/// Methods (Dart -> platform):
///   - `update`  args: { title, artist?, album?, durationMs?, positionMs?,
///                       playing?, artUri? }
///   - `clear`   args: {}
///   - `setEnabled` args: { enabled }
/// Methods (platform -> Dart) via `setMethodCallHandler`:
///   - `command` args: { action: play|pause|toggle|next|previous|stop|seek,
///                       positionMs? }
class MediaSessionService {
  MediaSessionService({required this.debugLog});

  final DebugLogService debugLog;
  static const _channel = MethodChannel('run.rosie.dacx/media_session');

  bool _enabled = false;
  bool _platformAvailable = true;
  String? _lastTitle;
  Duration _lastDuration = Duration.zero;

  _MprisAdapter? _mpris;

  final StreamController<MediaSessionCommand> _commandsCtrl =
      StreamController<MediaSessionCommand>.broadcast();

  Stream<MediaSessionCommand> get commands => _commandsCtrl.stream;

  Future<void> init({required bool enabled}) async {
    _enabled = enabled;
    if (!_supportedPlatform) {
      _platformAvailable = false;
      return;
    }
    if (Platform.isLinux) {
      try {
        _mpris = _MprisAdapter(_commandsCtrl.add, debugLog);
      } catch (e) {
        _platformAvailable = false;
        debugLog.log(
          category: DebugLogCategory.system,
          event: 'media_session_mpris_init_failed',
          message: e.toString(),
          severity: DebugSeverity.warn,
        );
      }
      return;
    }
    _channel.setMethodCallHandler(_handleNativeCall);
    await _safeInvoke('setEnabled', {'enabled': enabled});
  }

  bool get _supportedPlatform =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (Platform.isLinux) {
      _mpris?.setEnabled(enabled);
      if (!enabled) await clear();
      return;
    }
    await _safeInvoke('setEnabled', {'enabled': enabled});
    if (!enabled) await clear();
  }

  Future<void> updateMetadata({
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    String? artUri,
  }) async {
    if (!_enabled || !_platformAvailable) return;
    _lastTitle = title;
    if (duration != null) _lastDuration = duration;
    if (Platform.isLinux) {
      _mpris?.updateMetadata(
        title: title,
        artist: artist,
        album: album,
        duration: _lastDuration,
        artUri: artUri,
      );
      return;
    }
    await _safeInvoke('update', {
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': _lastDuration.inMilliseconds,
      'artUri': artUri,
    });
  }

  Future<void> updatePosition(
    Duration position, {
    required bool playing,
  }) async {
    if (!_enabled || !_platformAvailable) return;
    if (Platform.isLinux) {
      _mpris?.applyPosition(position, playing: playing);
      return;
    }
    await _safeInvoke('update', {
      'title': _lastTitle ?? '',
      'positionMs': position.inMilliseconds,
      'playing': playing,
      'durationMs': _lastDuration.inMilliseconds,
    });
  }

  Future<void> clear() async {
    if (!_platformAvailable) return;
    _lastTitle = null;
    _lastDuration = Duration.zero;
    if (Platform.isLinux) {
      _mpris?.clear();
      return;
    }
    await _safeInvoke('clear', const {});
  }

  Future<void> dispose() async {
    if (_mpris != null) {
      await _mpris!.dispose();
      _mpris = null;
    }
    await _commandsCtrl.close();
  }

  Future<void> _safeInvoke(String method, Map<String, Object?> args) async {
    if (!_platformAvailable) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      _platformAvailable = false;
      debugLog.log(
        category: DebugLogCategory.system,
        event: 'media_session_unavailable',
        message: 'Native media session bridge not registered for this platform',
        severity: DebugSeverity.info,
      );
    } catch (e) {
      debugLog.log(
        category: DebugLogCategory.system,
        event: 'media_session_error',
        message: '$method failed: $e',
        severity: DebugSeverity.warn,
      );
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final action = args['action']?.toString() ?? '';
    final positionMs = (args['positionMs'] as num?)?.toInt();
    _commandsCtrl.add(MediaSessionCommand(action, positionMs));
    return null;
  }
}

class MediaSessionCommand {
  const MediaSessionCommand(this.action, this.positionMs);
  final String action;
  final int? positionMs;
}

/// Linux MPRIS adapter built atop `anni_mpris_service`.
class _MprisAdapter extends MPRISService {
  _MprisAdapter(this._dispatch, this._log)
    : super(
        'dacx',
        identity: 'DACX',
        desktopEntry: 'run.rosie.dacx',
        emitSeekedSignal: true,
        canPlay: true,
        canPause: true,
        canGoNext: true,
        canGoPrevious: true,
        canSeek: true,
      );

  final void Function(MediaSessionCommand) _dispatch;
  final DebugLogService _log;
  bool _enabled = true;

  void setEnabled(bool v) {
    _enabled = v;
  }

  void updateMetadata({
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    String? artUri,
  }) {
    if (!_enabled) return;
    final id = '/run/rosie/dacx/track/${title.hashCode.toUnsigned(31)}';
    metadata = Metadata(
      trackId: id,
      trackTitle: title,
      trackArtist: artist == null ? null : <String>[artist],
      albumName: album,
      trackLength: duration,
      artUrl: artUri,
    );
  }

  void applyPosition(Duration position, {required bool playing}) {
    if (!_enabled) return;
    playbackStatus = playing ? PlaybackStatus.playing : PlaybackStatus.paused;
    updatePosition(position);
  }

  void clear() {
    metadata = Metadata(trackId: '/', trackTitle: '');
    playbackStatus = PlaybackStatus.stopped;
  }

  @override
  Future<void> onPlay() async =>
      _dispatch(const MediaSessionCommand('play', null));
  @override
  Future<void> onPause() async =>
      _dispatch(const MediaSessionCommand('pause', null));
  @override
  Future<void> onPlayPause() async =>
      _dispatch(const MediaSessionCommand('toggle', null));
  @override
  Future<void> onNext() async =>
      _dispatch(const MediaSessionCommand('next', null));
  @override
  Future<void> onPrevious() async =>
      _dispatch(const MediaSessionCommand('previous', null));
  @override
  Future<void> onStop() async =>
      _dispatch(const MediaSessionCommand('stop', null));
  @override
  Future<void> onSeek(int offset) async =>
      _dispatch(const MediaSessionCommand('seek', null));
  @override
  Future<void> onSetPosition(String trackId, int position) async {
    _dispatch(MediaSessionCommand('seek', position ~/ 1000));
  }

  @override
  Future<void> onLoopStatus(LoopStatus loopStatus) async {
    _log.log(
      category: DebugLogCategory.system,
      event: 'mpris_loop_status_request',
      message: loopStatus.toString(),
      severity: DebugSeverity.info,
    );
  }

  @override
  Future<void> onShuffle(bool shuffle) async {
    _log.log(
      category: DebugLogCategory.system,
      event: 'mpris_shuffle_request',
      message: shuffle.toString(),
      severity: DebugSeverity.info,
    );
  }
}
