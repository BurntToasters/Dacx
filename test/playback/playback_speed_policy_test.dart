import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/playback_speed_policy.dart';

void main() {
  group('PlaybackSpeedPolicy', () {
    test('cycleNext wraps presets', () {
      expect(PlaybackSpeedPolicy.cycleNext(1.0), 1.25);
      expect(PlaybackSpeedPolicy.cycleNext(2.0), 0.5);
    });

    test('stepSlower and stepFaster clamp at ends', () {
      expect(PlaybackSpeedPolicy.stepSlower(0.5), 0.5);
      expect(PlaybackSpeedPolicy.stepFaster(2.0), 2.0);
      expect(PlaybackSpeedPolicy.stepFaster(1.0), 1.25);
      expect(PlaybackSpeedPolicy.stepSlower(1.0), 0.75);
    });

    test('nearestPreset snaps off-grid rates', () {
      expect(PlaybackSpeedPolicy.nearestPreset(1.1), 1.0);
      expect(PlaybackSpeedPolicy.nearestPreset(1.4), 1.5);
    });

    test('formatLabel uses compact integer rates', () {
      expect(PlaybackSpeedPolicy.formatLabel(1.0), '1×');
      expect(PlaybackSpeedPolicy.formatLabel(1.25), '1.25×');
    });
  });
}
