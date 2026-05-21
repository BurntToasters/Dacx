import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/media_session_throttle.dart';

void main() {
  test('allows first send and blocks rapid follow-ups', () {
    final throttle = MediaSessionPositionThrottle(
      minInterval: const Duration(milliseconds: 100),
    );
    final t0 = DateTime(2020, 1, 1, 12, 0, 0);
    expect(throttle.shouldSend(t0), isTrue);
    expect(
      throttle.shouldSend(t0.add(const Duration(milliseconds: 50))),
      isFalse,
    );
    expect(
      throttle.shouldSend(t0.add(const Duration(milliseconds: 150))),
      isTrue,
    );
  });

  test('reset clears throttle state', () {
    final throttle = MediaSessionPositionThrottle();
    final t = DateTime(2020);
    throttle.shouldSend(t);
    throttle.reset();
    expect(throttle.shouldSend(t), isTrue);
  });
}
