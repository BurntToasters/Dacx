import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/source_load_pre_open_policy.dart';

void main() {
  group('SourceLoadPreOpenPolicy.shouldAbortBeforeOpen', () {
    test('aborts when widget is unmounted or controller is disposed', () {
      expect(
        SourceLoadPreOpenPolicy.shouldAbortBeforeOpen(
          mounted: false,
          isDisposed: false,
        ),
        isTrue,
      );
      expect(
        SourceLoadPreOpenPolicy.shouldAbortBeforeOpen(
          mounted: true,
          isDisposed: true,
        ),
        isTrue,
      );
      expect(
        SourceLoadPreOpenPolicy.shouldAbortBeforeOpen(
          mounted: true,
          isDisposed: false,
        ),
        isFalse,
      );
    });
  });
}
