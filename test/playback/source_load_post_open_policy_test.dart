import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/source_load_post_open_policy.dart';

void main() {
  group('SourceLoadPostOpenPolicy.plan', () {
    test('returns no-op plan when load generation is stale', () {
      final plan = SourceLoadPostOpenPolicy.plan(
        isLoadCurrent: false,
        isDisposed: false,
        mounted: true,
        normalizedSource: PlayableSource.file('/media/movie.mp4'),
        isAudioFile: false,
      );

      expect(plan.shouldProceed, isFalse);
      expect(plan.shouldRefreshUi, isFalse);
      expect(plan.seekPreviewPath, isNull);
      expect(plan.shouldPersistRecent, isFalse);
      expect(plan.shouldApplyResume, isFalse);
    });

    test('plans seek preview for video files', () {
      final plan = SourceLoadPostOpenPolicy.plan(
        isLoadCurrent: true,
        isDisposed: false,
        mounted: true,
        normalizedSource: PlayableSource.file('/media/movie.mp4'),
        isAudioFile: false,
      );

      expect(plan.shouldProceed, isTrue);
      expect(plan.seekPreviewPath, '/media/movie.mp4');
      expect(plan.shouldPersistRecent, isTrue);
      expect(plan.shouldRememberOpenDirectory, isTrue);
      expect(plan.resumeTrackingPath, '/media/movie.mp4');
      expect(plan.shouldApplyResume, isTrue);
      expect(plan.recentPersistLogEvent, 'recent_file_added');
    });

    test('skips seek preview and resume for audio files', () {
      final plan = SourceLoadPostOpenPolicy.plan(
        isLoadCurrent: true,
        isDisposed: false,
        mounted: true,
        normalizedSource: PlayableSource.file('/media/song.mp3'),
        isAudioFile: true,
      );

      expect(plan.seekPreviewPath, isNull);
      expect(plan.shouldApplyResume, isTrue);
      expect(plan.resumeTrackingPath, '/media/song.mp3');
    });

    test('skips recent persistence for unsafe URLs', () {
      final plan = SourceLoadPostOpenPolicy.plan(
        isLoadCurrent: true,
        isDisposed: false,
        mounted: true,
        normalizedSource: PlayableSource.url('https://user:pass@host/live'),
        isAudioFile: false,
      );

      expect(plan.shouldPersistRecent, isFalse);
      expect(plan.shouldRememberOpenDirectory, isFalse);
      expect(plan.resumeTrackingPath, isNull);
      expect(plan.shouldApplyResume, isFalse);
      expect(plan.recentPersistLogEvent, 'recent_url_skipped');
    });

    test('does not refresh UI when widget is unmounted', () {
      final plan = SourceLoadPostOpenPolicy.plan(
        isLoadCurrent: true,
        isDisposed: false,
        mounted: false,
        normalizedSource: PlayableSource.file('/media/movie.mp4'),
        isAudioFile: false,
      );

      expect(plan.shouldProceed, isTrue);
      expect(plan.shouldRefreshUi, isFalse);
    });
  });
}
