import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/settings_service.dart';

/// High-level effect produced by a [MediaSessionCommand].
enum MediaSessionDispatchKind {
  play,
  pause,
  toggle,
  stop,
  next,
  previous,
  seek,
  setLoopMode,
  setShuffle,
  setVolume,
  setRate,
  noop,
}

class MediaSessionDispatch {
  const MediaSessionDispatch(
    this.kind, {
    this.seekTarget,
    this.loopMode,
    this.shuffle,
    this.volumePercent,
    this.rate,
  });

  final MediaSessionDispatchKind kind;
  final Duration? seekTarget;
  final LoopMode? loopMode;
  final bool? shuffle;
  final double? volumePercent;
  final double? rate;
}

/// Pure command-to-effect mapping for the media session bridge.
abstract final class MediaSessionCommandDispatch {
  static MediaSessionDispatch resolve(
    MediaSessionCommand cmd, {
    required Duration position,
    required Duration duration,
  }) {
    switch (cmd.action) {
      case 'play':
        return const MediaSessionDispatch(MediaSessionDispatchKind.play);
      case 'pause':
        return const MediaSessionDispatch(MediaSessionDispatchKind.pause);
      case 'toggle':
        return const MediaSessionDispatch(MediaSessionDispatchKind.toggle);
      case 'stop':
        return const MediaSessionDispatch(MediaSessionDispatchKind.stop);
      case 'next':
        return const MediaSessionDispatch(MediaSessionDispatchKind.next);
      case 'previous':
        return const MediaSessionDispatch(MediaSessionDispatchKind.previous);
      case 'seek':
        if (cmd.positionMs == null) {
          return const MediaSessionDispatch(MediaSessionDispatchKind.noop);
        }
        return MediaSessionDispatch(
          MediaSessionDispatchKind.seek,
          seekTarget: Duration(milliseconds: cmd.positionMs!),
        );
      case 'seek_relative':
        if (cmd.positionMs == null) {
          return const MediaSessionDispatch(MediaSessionDispatchKind.noop);
        }
        final target = position + Duration(milliseconds: cmd.positionMs!);
        return MediaSessionDispatch(
          MediaSessionDispatchKind.seek,
          seekTarget: Duration(
            milliseconds: target.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            ),
          ),
        );
      case 'loop':
        final v = cmd.value ?? 0.0;
        final mode = v >= 1.5
            ? LoopMode.loop
            : (v >= 0.5 ? LoopMode.single : LoopMode.none);
        return MediaSessionDispatch(
          MediaSessionDispatchKind.setLoopMode,
          loopMode: mode,
        );
      case 'shuffle':
        return MediaSessionDispatch(
          MediaSessionDispatchKind.setShuffle,
          shuffle: (cmd.value ?? 0.0) > 0.5,
        );
      case 'volume':
        final v = (cmd.value ?? 0.0).clamp(0.0, 1.0);
        return MediaSessionDispatch(
          MediaSessionDispatchKind.setVolume,
          volumePercent: v * 100.0,
        );
      case 'rate':
        final r = (cmd.value ?? 1.0).clamp(0.25, 4.0);
        return MediaSessionDispatch(MediaSessionDispatchKind.setRate, rate: r);
      default:
        return const MediaSessionDispatch(MediaSessionDispatchKind.noop);
    }
  }
}
