import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/load_outcome_policy.dart';
import 'package:dacx/playback/playback_controller.dart';

void main() {
  group('LoadOutcomePolicy', () {
    test(
      'shouldProceedAfterOpen requires current generation and alive state',
      () {
        expect(
          LoadOutcomePolicy.shouldProceedAfterOpen(
            isLoadCurrent: true,
            isDisposed: false,
          ),
          isTrue,
        );
        expect(
          LoadOutcomePolicy.shouldProceedAfterOpen(
            isLoadCurrent: false,
            isDisposed: false,
          ),
          isFalse,
        );
        expect(
          LoadOutcomePolicy.shouldProceedAfterOpen(
            isLoadCurrent: true,
            isDisposed: true,
          ),
          isFalse,
        );
      },
    );

    test('shouldRefreshUi requires mounted alive current generation', () {
      expect(
        LoadOutcomePolicy.shouldRefreshUi(
          mounted: true,
          isDisposed: false,
          isLoadCurrent: true,
        ),
        isTrue,
      );
      expect(
        LoadOutcomePolicy.shouldRefreshUi(
          mounted: false,
          isDisposed: false,
          isLoadCurrent: true,
        ),
        isFalse,
      );
      expect(
        LoadOutcomePolicy.shouldRefreshUi(
          mounted: true,
          isDisposed: false,
          isLoadCurrent: false,
        ),
        isFalse,
      );
    });
  });

  group('LoadOutcomePolicy with PlaybackController', () {
    test('superseded load generation does not proceed after open', () {
      final playback = PlaybackController();
      final staleGen = playback.beginLoad();
      playback.beginLoad();

      expect(
        LoadOutcomePolicy.shouldProceedAfterOpen(
          isLoadCurrent: playback.isLoadCurrent(staleGen),
          isDisposed: false,
        ),
        isFalse,
      );
      playback.dispose();
    });
  });
}
