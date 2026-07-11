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

  group('SourceOpenPolicy.paramsFor', () {
    test('bundles path and autoplay decision', () {
      final params = SourceOpenPolicy.paramsFor(
        normalizedPath: '/media/song.mp3',
        forcePlay: false,
        autoPlaySetting: false,
      );
      expect(params.path, '/media/song.mp3');
      expect(params.play, isFalse);
    });
  });

  group('SourceOpenPolicy.shouldResumeSameFile', () {
    test('resumes only when forcePlay and currently paused', () {
      expect(
        SourceOpenPolicy.shouldResumeSameFile(
          forcePlay: true,
          isPlaying: false,
        ),
        isTrue,
      );
      expect(
        SourceOpenPolicy.shouldResumeSameFile(forcePlay: true, isPlaying: true),
        isFalse,
      );
      expect(
        SourceOpenPolicy.shouldResumeSameFile(
          forcePlay: false,
          isPlaying: false,
        ),
        isFalse,
      );
    });
  });

  group('SourceOpenPolicy.shouldRestartSameFile', () {
    test('restarts only when forcePlay and currently playing', () {
      expect(
        SourceOpenPolicy.shouldRestartSameFile(
          forcePlay: true,
          isPlaying: true,
        ),
        isTrue,
      );
      expect(
        SourceOpenPolicy.shouldRestartSameFile(
          forcePlay: true,
          isPlaying: false,
        ),
        isFalse,
      );
      expect(
        SourceOpenPolicy.shouldRestartSameFile(
          forcePlay: false,
          isPlaying: true,
        ),
        isFalse,
      );
    });
  });

  group('SourceOpenPolicy.shouldForcePlaySameFile (deprecated)', () {
    test('matches shouldResumeSameFile', () {
      // ignore: deprecated_member_use_from_same_package
      expect(
        SourceOpenPolicy.shouldForcePlaySameFile(
          forcePlay: true,
          isPlaying: false,
        ),
        SourceOpenPolicy.shouldResumeSameFile(
          forcePlay: true,
          isPlaying: false,
        ),
      );
      // ignore: deprecated_member_use_from_same_package
      expect(
        SourceOpenPolicy.shouldForcePlaySameFile(
          forcePlay: true,
          isPlaying: true,
        ),
        SourceOpenPolicy.shouldResumeSameFile(forcePlay: true, isPlaying: true),
      );
    });
  });
}
