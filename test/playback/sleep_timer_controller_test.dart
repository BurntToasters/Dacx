import 'package:dacx/playback/sleep_timer_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SleepTimerController.computeRemaining', () {
    test('returns null when inactive', () {
      expect(
        SleepTimerController.computeRemaining(
          endsAt: null,
          now: DateTime(2020),
        ),
        isNull,
      );
    });

    test('returns remaining duration', () {
      final now = DateTime(2020, 1, 1, 12, 0);
      final ends = now.add(const Duration(minutes: 15, seconds: 30));
      expect(
        SleepTimerController.computeRemaining(endsAt: ends, now: now),
        const Duration(minutes: 15, seconds: 30),
      );
    });

    test('clamps overdue remaining to zero', () {
      final now = DateTime(2020, 1, 1, 12, 0);
      final ends = now.subtract(const Duration(seconds: 5));
      expect(
        SleepTimerController.computeRemaining(endsAt: ends, now: now),
        Duration.zero,
      );
    });
  });

  group('SleepTimerController', () {
    test('presets are 15/30/45/60', () {
      expect(SleepTimerController.presetMinutes, [15, 30, 45, 60]);
    });

    test('start schedules fire and exposes remaining', () {
      fakeAsync((async) {
        final epoch = DateTime(2020);
        var fired = 0;
        final controller = SleepTimerController(
          clock: () => epoch.add(async.elapsed),
          onFire: () => fired++,
        );

        controller.start(const Duration(minutes: 15));
        expect(controller.isActive, isTrue);
        expect(controller.remaining, const Duration(minutes: 15));

        async.elapse(const Duration(minutes: 10));
        expect(controller.remaining, const Duration(minutes: 5));
        expect(fired, 0);

        async.elapse(const Duration(minutes: 5));
        expect(fired, 1);
        expect(controller.isActive, isFalse);
        expect(controller.remaining, isNull);

        controller.dispose();
      });
    });

    test('cancel prevents fire', () {
      fakeAsync((async) {
        final epoch = DateTime(2020);
        var fired = 0;
        final controller = SleepTimerController(
          clock: () => epoch.add(async.elapsed),
          onFire: () => fired++,
        );

        controller.startMinutes(30);
        expect(controller.isActive, isTrue);
        controller.cancel();
        expect(controller.isActive, isFalse);
        expect(controller.remaining, isNull);

        async.elapse(const Duration(minutes: 30));
        expect(fired, 0);

        controller.dispose();
      });
    });

    test('restart replaces previous timer', () {
      fakeAsync((async) {
        final epoch = DateTime(2020);
        var fired = 0;
        final controller = SleepTimerController(
          clock: () => epoch.add(async.elapsed),
          onFire: () => fired++,
        );

        controller.startMinutes(60);
        async.elapse(const Duration(minutes: 10));
        controller.startMinutes(15);
        expect(controller.remaining, const Duration(minutes: 15));

        async.elapse(const Duration(minutes: 15));
        expect(fired, 1);

        // Original 60m timer must not fire later.
        async.elapse(const Duration(minutes: 50));
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('notifies listeners on start, tick, cancel, and fire', () {
      fakeAsync((async) {
        final epoch = DateTime(2020);
        var notifications = 0;
        final controller = SleepTimerController(
          clock: () => epoch.add(async.elapsed),
        )..addListener(() => notifications++);

        controller.start(const Duration(seconds: 3));
        expect(notifications, 1);

        async.elapse(const Duration(seconds: 1));
        expect(notifications, greaterThan(1));
        final afterTick = notifications;

        controller.cancel();
        expect(notifications, afterTick + 1);

        controller.start(const Duration(seconds: 2));
        final beforeFire = notifications;
        async.elapse(const Duration(seconds: 2));
        expect(notifications, greaterThan(beforeFire));

        controller.dispose();
      });
    });

    test('zero or negative duration does not arm timer', () {
      fakeAsync((async) {
        var fired = 0;
        final controller = SleepTimerController(onFire: () => fired++);

        controller.start(Duration.zero);
        expect(controller.isActive, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(fired, 0);

        controller.dispose();
      });
    });
  });
}
