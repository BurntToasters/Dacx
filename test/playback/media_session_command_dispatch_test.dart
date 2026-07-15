import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/media_session_command_dispatch.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('MediaSessionCommandDispatch.resolve', () {
    test('maps play/pause/toggle/stop', () {
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('play', null),
          position: Duration.zero,
          duration: const Duration(minutes: 3),
        ).kind,
        MediaSessionDispatchKind.play,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('pause', null),
          position: Duration.zero,
          duration: const Duration(minutes: 3),
        ).kind,
        MediaSessionDispatchKind.pause,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('toggle', null),
          position: Duration.zero,
          duration: const Duration(minutes: 3),
        ).kind,
        MediaSessionDispatchKind.toggle,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('stop', null),
          position: Duration.zero,
          duration: const Duration(minutes: 3),
        ).kind,
        MediaSessionDispatchKind.stop,
      );
    });

    test('maps playlist next and previous', () {
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('next', null),
          position: Duration.zero,
          duration: Duration.zero,
        ).kind,
        MediaSessionDispatchKind.next,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('previous', null),
          position: Duration.zero,
          duration: Duration.zero,
        ).kind,
        MediaSessionDispatchKind.previous,
      );
    });

    test('maps absolute seek', () {
      final dispatch = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('seek', 90_000),
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 5),
      );
      expect(dispatch.kind, MediaSessionDispatchKind.seek);
      expect(dispatch.seekTarget, const Duration(milliseconds: 90_000));
    });

    test('maps relative seek with clamping', () {
      final dispatch = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('seek_relative', 120_000),
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 5),
      );
      expect(dispatch.kind, MediaSessionDispatchKind.seek);
      expect(dispatch.seekTarget, const Duration(minutes: 5));
    });

    test('returns noop when seek commands lack position', () {
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('seek', null),
          position: Duration.zero,
          duration: const Duration(minutes: 1),
        ).kind,
        MediaSessionDispatchKind.noop,
      );
    });

    test('maps loop values to loop modes', () {
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('loop', null, value: 0.0),
          position: Duration.zero,
          duration: Duration.zero,
        ).loopMode,
        LoopMode.none,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('loop', null, value: 0.5),
          position: Duration.zero,
          duration: Duration.zero,
        ).loopMode,
        LoopMode.single,
      );
      expect(
        MediaSessionCommandDispatch.resolve(
          const MediaSessionCommand('loop', null, value: 2.0),
          position: Duration.zero,
          duration: Duration.zero,
        ).loopMode,
        LoopMode.loop,
      );
    });

    test('maps shuffle and volume', () {
      final shuffle = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('shuffle', null, value: 1.0),
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(shuffle.kind, MediaSessionDispatchKind.setShuffle);
      expect(shuffle.shuffle, isTrue);

      final volume = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('volume', null, value: 0.5),
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(volume.kind, MediaSessionDispatchKind.setVolume);
      expect(volume.volumePercent, 50.0);
    });

    test('clamps rate between 0.25 and 4.0', () {
      final low = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('rate', null, value: 0.1),
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(low.rate, 0.25);

      final high = MediaSessionCommandDispatch.resolve(
        const MediaSessionCommand('rate', null, value: 9.0),
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(high.rate, 4.0);
    });
  });
}
