import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/source_load_policy.dart';

void main() {
  group('SourceLoadPolicy.shouldPersistToRecents', () {
    test('persists local files', () {
      expect(
        SourceLoadPolicy.shouldPersistToRecents(
          PlayableSource.file('/media/song.mp3'),
        ),
        isTrue,
      );
    });

    test('persists display-safe URLs', () {
      expect(
        SourceLoadPolicy.shouldPersistToRecents(
          PlayableSource.url('https://example.com/live.m3u8'),
        ),
        isTrue,
      );
    });

    test('skips URLs with embedded credentials', () {
      expect(
        SourceLoadPolicy.shouldPersistToRecents(
          PlayableSource.url('https://user:secret@example.com/live'),
        ),
        isFalse,
      );
    });
  });

  group('SourceLoadPolicy.seekPreviewFilePath', () {
    test('returns file path for non-audio video files', () {
      expect(
        SourceLoadPolicy.seekPreviewFilePath(
          source: PlayableSource.file('/media/movie.mp4'),
          isAudioFile: false,
        ),
        '/media/movie.mp4',
      );
    });

    test('returns null for audio files and streams', () {
      expect(
        SourceLoadPolicy.seekPreviewFilePath(
          source: PlayableSource.file('/media/song.mp3'),
          isAudioFile: true,
        ),
        isNull,
      );
      expect(
        SourceLoadPolicy.seekPreviewFilePath(
          source: PlayableSource.url('https://example.com/live'),
          isAudioFile: false,
        ),
        isNull,
      );
    });
  });

  group('SourceLoadPolicy.resumeTrackingPath', () {
    test('tracks local files only', () {
      expect(
        SourceLoadPolicy.resumeTrackingPath(
          PlayableSource.file('/media/song.mp3'),
        ),
        '/media/song.mp3',
      );
      expect(
        SourceLoadPolicy.resumeTrackingPath(
          PlayableSource.url('https://example.com/live'),
        ),
        isNull,
      );
    });
  });

  group('SourceLoadPolicy post-load helpers', () {
    test('applies resume and remembers directory for local files', () {
      final file = PlayableSource.file('/media/song.mp3');
      expect(SourceLoadPolicy.shouldApplyResume(file), isTrue);
      expect(SourceLoadPolicy.shouldRememberOpenDirectory(file), isTrue);
      expect(SourceLoadPolicy.recentPersistLogEvent(file), 'recent_file_added');
    });

    test('skips resume and directory for remote streams', () {
      final url = PlayableSource.url('https://example.com/live.m3u8');
      expect(SourceLoadPolicy.shouldApplyResume(url), isFalse);
      expect(SourceLoadPolicy.shouldRememberOpenDirectory(url), isFalse);
      expect(SourceLoadPolicy.recentPersistLogEvent(url), 'recent_file_added');
    });

    test('logs skipped recents for unsafe URLs', () {
      final unsafe = PlayableSource.url('https://user:pass@example.com/live');
      expect(
        SourceLoadPolicy.recentPersistLogEvent(unsafe),
        'recent_url_skipped',
      );
    });
  });
}
