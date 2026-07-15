import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dacx/playback/screenshot_path_policy.dart';

void main() {
  group('ScreenshotPathPolicy', () {
    test('mimeForFormat maps png and defaults to jpeg', () {
      expect(ScreenshotPathPolicy.mimeForFormat('png'), 'image/png');
      expect(ScreenshotPathPolicy.mimeForFormat('jpg'), 'image/jpeg');
    });

    test('sanitizeBaseName strips unsafe characters and whitespace', () {
      expect(
        ScreenshotPathPolicy.sanitizeBaseName(' my:video?.mp4 '),
        'my_video_.mp4',
      );
    });

    test('baseNameForSource uses file basename or display name', () {
      expect(
        ScreenshotPathPolicy.baseNameForSource(
          isFile: true,
          sourceValue: '/media/My Movie.mkv',
          displayName: 'ignored',
        ),
        'My_Movie',
      );
      expect(
        ScreenshotPathPolicy.baseNameForSource(
          isFile: false,
          sourceValue: 'https://example.com/live',
          displayName: 'Live Stream',
        ),
        'Live_Stream',
      );
    });

    test('buildOutputPath joins directory, base, timestamp, and format', () {
      final path = ScreenshotPathPolicy.buildOutputPath(
        directory: '/tmp/shots',
        baseName: 'clip',
        format: 'png',
        timestamp: DateTime.utc(2026, 3, 21, 14, 30, 45, 123),
      );
      expect(path, p.join('/tmp/shots', 'clip_2026-03-21T14-30-45-123Z.png'));
    });

    test(
      'timestampToken keeps milliseconds to avoid same-second collisions',
      () {
        final a = ScreenshotPathPolicy.timestampToken(
          DateTime.utc(2026, 3, 21, 14, 30, 45, 1),
        );
        final b = ScreenshotPathPolicy.timestampToken(
          DateTime.utc(2026, 3, 21, 14, 30, 45, 2),
        );
        expect(a, isNot(b));
        expect(a, contains('14-30-45-001'));
        expect(b, contains('14-30-45-002'));
      },
    );
  });
}
