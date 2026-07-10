import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/source_load_open_policy.dart';
import 'package:dacx/playback/source_load_validation_policy.dart';

void main() {
  group('SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension', () {
    test('warns for non-empty unsupported extensions', () {
      expect(
        SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension(
          isFile: true,
          ext: 'xyz',
        ),
        isTrue,
      );
      expect(
        SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension(
          isFile: true,
          ext: '',
        ),
        isFalse,
      );
      expect(
        SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension(
          isFile: true,
          ext: 'mp3',
        ),
        isFalse,
      );
      expect(
        SourceLoadOpenPolicy.shouldWarnUnrecognizedExtension(
          isFile: false,
          ext: 'xyz',
        ),
        isFalse,
      );
    });
  });

  group('SourceLoadOpenPolicy.openFailureReaction', () {
    test('updates ui only for current loads on mounted widgets', () {
      expect(
        SourceLoadOpenPolicy.openFailureReaction(
          kind: SourceLoadFailureKind.generic,
          isLoadCurrent: true,
          mounted: true,
        ).shouldUpdateUi,
        isTrue,
      );
      expect(
        SourceLoadOpenPolicy.openFailureReaction(
          kind: SourceLoadFailureKind.generic,
          isLoadCurrent: false,
          mounted: true,
        ).shouldUpdateUi,
        isFalse,
      );
      expect(
        SourceLoadOpenPolicy.openFailureReaction(
          kind: SourceLoadFailureKind.generic,
          isLoadCurrent: true,
          mounted: false,
        ).shouldUpdateUi,
        isFalse,
      );
    });

    test('logs permission failures as warnings', () {
      expect(
        SourceLoadOpenPolicy.openFailureReaction(
          kind: SourceLoadFailureKind.permissionDenied,
          isLoadCurrent: true,
          mounted: true,
        ).logAsWarning,
        isTrue,
      );
      expect(
        SourceLoadOpenPolicy.openFailureReaction(
          kind: SourceLoadFailureKind.generic,
          isLoadCurrent: true,
          mounted: true,
        ).logAsWarning,
        isFalse,
      );
    });
  });
}
