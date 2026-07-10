import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/update_launch_policy.dart';

void main() {
  group('UpdateLaunchPolicy.decide', () {
    const now = 1_700_000_000_000;

    test('returns none when marker is null', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: null,
        nowEpochMs: now,
        actualVersion: '0.10.0',
      );
      expect(decision.shouldShow, isFalse);
    });

    test('returns none when target_version is missing', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: {'started_at_ms': now},
        nowEpochMs: now,
        actualVersion: '0.10.0',
      );
      expect(decision.shouldShow, isFalse);
    });

    test('drops markers older than max age', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: {
          'target_version': '0.10.0',
          'started_at_ms': now - const Duration(days: 8).inMilliseconds,
        },
        nowEpochMs: now,
        actualVersion: '0.10.0',
      );
      expect(decision.shouldShow, isFalse);
    });

    test('returns success when actual version matches target', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: {
          'target_version': '0.10.0',
          'started_at_ms': now - const Duration(hours: 1).inMilliseconds,
        },
        nowEpochMs: now,
        actualVersion: '0.10.0',
      );
      expect(decision.kind, UpdateLaunchNoticeKind.success);
      expect(decision.targetVersion, '0.10.0');
    });

    test('returns failed when actual version differs from target', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: {'target_version': '0.10.0', 'started_at_ms': now},
        nowEpochMs: now,
        actualVersion: '0.9.9',
      );
      expect(decision.kind, UpdateLaunchNoticeKind.failed);
      expect(decision.targetVersion, '0.10.0');
    });

    test('accepts marker without started_at_ms', () {
      final decision = UpdateLaunchPolicy.decide(
        marker: {'target_version': '0.10.0'},
        nowEpochMs: now,
        actualVersion: '0.10.0',
      );
      expect(decision.kind, UpdateLaunchNoticeKind.success);
    });
  });
}
