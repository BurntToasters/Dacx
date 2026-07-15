import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/track_cycle_policy.dart';

void main() {
  group('TrackCyclePolicy', () {
    test('canCycle requires more than one selectable track', () {
      expect(TrackCyclePolicy.canCycle(selectableCount: 2), isTrue);
      expect(TrackCyclePolicy.canCycle(selectableCount: 1), isFalse);
    });

    test('nextIndex wraps and starts from first when current is unknown', () {
      expect(TrackCyclePolicy.nextIndex(currentIndex: -1, listLength: 3), 0);
      expect(TrackCyclePolicy.nextIndex(currentIndex: 1, listLength: 3), 2);
      expect(TrackCyclePolicy.nextIndex(currentIndex: 2, listLength: 3), 0);
    });
  });
}
