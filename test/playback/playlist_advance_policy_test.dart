import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/playlist_advance_policy.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('PlaylistAdvancePolicy.shouldWrapQueue', () {
    test('wraps only for loop-all mode', () {
      expect(PlaylistAdvancePolicy.shouldWrapQueue(LoopMode.loop), isTrue);
      expect(PlaylistAdvancePolicy.shouldWrapQueue(LoopMode.none), isFalse);
      expect(PlaylistAdvancePolicy.shouldWrapQueue(LoopMode.single), isFalse);
    });
  });

  group('PlaylistAdvancePolicy.shouldAdvanceOnCompleted', () {
    test('skips auto-advance only for loop-single mode', () {
      expect(
        PlaylistAdvancePolicy.shouldAdvanceOnCompleted(LoopMode.single),
        isFalse,
      );
      expect(
        PlaylistAdvancePolicy.shouldAdvanceOnCompleted(LoopMode.none),
        isTrue,
      );
      expect(
        PlaylistAdvancePolicy.shouldAdvanceOnCompleted(LoopMode.loop),
        isTrue,
      );
    });
  });
}
