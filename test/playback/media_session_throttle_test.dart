import 'dart:async';

import 'package:dacx/playback/media_session_throttle.dart';
import 'package:dacx/playback/subscription_bag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaSessionPositionThrottle', () {
    late MediaSessionPositionThrottle throttle;

    setUp(() {
      throttle = MediaSessionPositionThrottle(
        minInterval: const Duration(milliseconds: 400),
      );
    });

    test('first call always returns true', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      expect(throttle.shouldSend(now), isTrue);
    });

    test('second call within interval returns false', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      throttle.shouldSend(now);
      final soon = now.add(const Duration(milliseconds: 200));
      expect(throttle.shouldSend(soon), isFalse);
    });

    test('call after interval returns true', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      throttle.shouldSend(now);
      final later = now.add(const Duration(milliseconds: 500));
      expect(throttle.shouldSend(later), isTrue);
    });

    test('call exactly at interval boundary returns true', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      throttle.shouldSend(now);
      final exact = now.add(const Duration(milliseconds: 400));
      expect(throttle.shouldSend(exact), isTrue);
    });

    test('reset allows immediate send', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      throttle.shouldSend(now);
      throttle.reset();
      final soon = now.add(const Duration(milliseconds: 100));
      expect(throttle.shouldSend(soon), isTrue);
    });

    test('custom minInterval is honored', () {
      final fast = MediaSessionPositionThrottle(
        minInterval: const Duration(milliseconds: 50),
      );
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      fast.shouldSend(now);
      final after = now.add(const Duration(milliseconds: 60));
      expect(fast.shouldSend(after), isTrue);
    });
  });

  group('SubscriptionBag', () {
    test('add and cancelAll works', () async {
      final bag = SubscriptionBag();
      final controller = StreamController<int>.broadcast();
      var received = 0;

      bag.add(controller.stream.listen((_) => received++));

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(received, 1);

      bag.cancelAll();

      controller.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(received, 1); // Not incremented after cancel.

      await controller.close();
    });

    test('cancelAll on empty bag does not throw', () {
      final bag = SubscriptionBag();
      expect(() => bag.cancelAll(), returnsNormally);
    });

    test('multiple subscriptions are all cancelled', () async {
      final bag = SubscriptionBag();
      final c1 = StreamController<int>.broadcast();
      final c2 = StreamController<String>.broadcast();
      var count1 = 0;
      var count2 = 0;

      bag.add(c1.stream.listen((_) => count1++));
      bag.add(c2.stream.listen((_) => count2++));

      c1.add(1);
      c2.add('a');
      await Future<void>.delayed(Duration.zero);
      expect(count1, 1);
      expect(count2, 1);

      bag.cancelAll();

      c1.add(2);
      c2.add('b');
      await Future<void>.delayed(Duration.zero);
      expect(count1, 1);
      expect(count2, 1);

      await c1.close();
      await c2.close();
    });

    test('cancelAll clears the internal list', () async {
      final bag = SubscriptionBag();
      final controller = StreamController<int>.broadcast();
      bag.add(controller.stream.listen((_) {}));

      bag.cancelAll();
      // Second cancelAll should not throw or double-cancel.
      expect(() => bag.cancelAll(), returnsNormally);

      await controller.close();
    });
  });
}
