import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/source_open_policy.dart';

void main() {
  group('SourceOpenPolicy.shouldAutoplayOnOpen', () {
    test('autoplays when forcePlay is true', () {
      expect(
        SourceOpenPolicy.shouldAutoplayOnOpen(
          forcePlay: true,
          autoPlaySetting: false,
        ),
        isTrue,
      );
    });

    test('autoplays when setting is enabled', () {
      expect(
        SourceOpenPolicy.shouldAutoplayOnOpen(
          forcePlay: false,
          autoPlaySetting: true,
        ),
        isTrue,
      );
    });

    test('does not autoplay when both are false', () {
      expect(
        SourceOpenPolicy.shouldAutoplayOnOpen(
          forcePlay: false,
          autoPlaySetting: false,
        ),
        isFalse,
      );
    });
  });

  group('SourceOpenPolicy.shouldForcePlaySameFile', () {
    test('forces play only when requested and currently paused', () {
      expect(
        SourceOpenPolicy.shouldForcePlaySameFile(
          forcePlay: true,
          isPlaying: false,
        ),
        isTrue,
      );
      expect(
        SourceOpenPolicy.shouldForcePlaySameFile(
          forcePlay: true,
          isPlaying: true,
        ),
        isFalse,
      );
      expect(
        SourceOpenPolicy.shouldForcePlaySameFile(
          forcePlay: false,
          isPlaying: false,
        ),
        isFalse,
      );
    });
  });
}
