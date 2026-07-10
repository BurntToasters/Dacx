import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/chapter_navigation_policy.dart';
import 'package:dacx/playback/volume_policy.dart';

void main() {
  group('VolumePolicy', () {
    test('clampVolume keeps values in 0..100', () {
      expect(VolumePolicy.clampVolume(-5), 0);
      expect(VolumePolicy.clampVolume(150), 100);
      expect(VolumePolicy.clampVolume(42.5), 42.5);
    });

    test('adjustVolume applies delta then clamps', () {
      expect(VolumePolicy.adjustVolume(current: 50, delta: 10), 60);
      expect(VolumePolicy.adjustVolume(current: 95, delta: 10), 100);
      expect(VolumePolicy.adjustVolume(current: 5, delta: -10), 0);
    });

    test('toggleMute mutes and restores previous volume', () {
      final mute = VolumePolicy.toggleMute(
        currentVolume: 75,
        volumeBeforeMute: 50,
      );
      expect(mute.newVolume, 0);
      expect(mute.volumeBeforeMute, 75);

      final restore = VolumePolicy.toggleMute(
        currentVolume: 0,
        volumeBeforeMute: 75,
      );
      expect(restore.newVolume, 75);
      expect(restore.volumeBeforeMute, 75);
    });
  });

  group('ChapterNavigationPolicy.stepIndex', () {
    test('clamps to chapter bounds', () {
      expect(
        ChapterNavigationPolicy.stepIndex(
          currentIndex: 1,
          delta: 1,
          chapterCount: 3,
        ),
        2,
      );
      expect(
        ChapterNavigationPolicy.stepIndex(
          currentIndex: 0,
          delta: -1,
          chapterCount: 3,
        ),
        0,
      );
      expect(
        ChapterNavigationPolicy.stepIndex(
          currentIndex: 2,
          delta: 5,
          chapterCount: 3,
        ),
        2,
      );
    });

    test('returns zero when chapter list is empty', () {
      expect(
        ChapterNavigationPolicy.stepIndex(
          currentIndex: 0,
          delta: 1,
          chapterCount: 0,
        ),
        0,
      );
    });
  });
}
