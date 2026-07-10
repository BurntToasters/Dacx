import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/osd_policy.dart';
import 'package:dacx/playback/player_controller.dart';

void main() {
  group('OsdPolicy', () {
    test('shouldShow requires osd enabled and mounted widget', () {
      expect(OsdPolicy.shouldShow(osdEnabled: true, mounted: true), isTrue);
      expect(OsdPolicy.shouldShow(osdEnabled: false, mounted: true), isFalse);
      expect(OsdPolicy.shouldShow(osdEnabled: true, mounted: false), isFalse);
    });

    test('formatTransientMessage appends hidden timestamp suffix', () {
      expect(
        OsdPolicy.formatTransientMessage('Paused', timestampMs: 1234),
        'Paused\u2009·\u20091234',
      );
      expect(
        PlayerController.stripOsdTimestamp(
          OsdPolicy.formatTransientMessage('Paused', timestampMs: 1234),
        ),
        'Paused',
      );
    });
  });
}
