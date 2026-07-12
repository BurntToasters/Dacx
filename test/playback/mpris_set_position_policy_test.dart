import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/mpris_set_position_policy.dart';

void main() {
  group('MprisSetPositionPolicy', () {
    test('accepts matching active track ids', () {
      expect(
        MprisSetPositionPolicy.shouldSeek(
          requestedTrackId: '/run/rosie/dacx/track/1',
          currentTrackId: '/run/rosie/dacx/track/1',
        ),
        isTrue,
      );
    });

    test('rejects mismatched track ids', () {
      expect(
        MprisSetPositionPolicy.shouldSeek(
          requestedTrackId: '/run/rosie/dacx/track/old',
          currentTrackId: '/run/rosie/dacx/track/new',
        ),
        isFalse,
      );
    });

    test('rejects cleared or empty current track', () {
      expect(
        MprisSetPositionPolicy.shouldSeek(
          requestedTrackId: '/run/rosie/dacx/track/1',
          currentTrackId: '/',
        ),
        isFalse,
      );
      expect(
        MprisSetPositionPolicy.shouldSeek(
          requestedTrackId: '/run/rosie/dacx/track/1',
          currentTrackId: '',
        ),
        isFalse,
      );
    });
  });
}
