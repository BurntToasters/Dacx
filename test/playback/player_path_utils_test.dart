import 'dart:io';

import 'package:dacx/playback/player_path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerPathUtils', () {
    group('coerceOpenPath', () {
      test('string value returns trimmed path', () {
        expect(
          PlayerPathUtils.coerceOpenPath('  /tmp/file.mp3  '),
          '/tmp/file.mp3',
        );
      });

      test('empty string returns null', () {
        expect(PlayerPathUtils.coerceOpenPath(''), isNull);
      });

      test('whitespace-only string returns null', () {
        expect(PlayerPathUtils.coerceOpenPath('   '), isNull);
      });

      test('null returns null', () {
        expect(PlayerPathUtils.coerceOpenPath(null), isNull);
      });

      test('non-string non-map returns null', () {
        expect(PlayerPathUtils.coerceOpenPath(42), isNull);
      });

      test('map with path key returns path', () {
        expect(
          PlayerPathUtils.coerceOpenPath({'path': '/music/song.flac'}),
          '/music/song.flac',
        );
      });

      test('map with empty path returns null', () {
        expect(PlayerPathUtils.coerceOpenPath({'path': ''}), isNull);
      });

      test('map without path key returns null', () {
        expect(PlayerPathUtils.coerceOpenPath({'file': '/a.mp3'}), isNull);
      });
    });

    group('coerceOpenRequest', () {
      test('string returns request with path only', () {
        final req = PlayerPathUtils.coerceOpenRequest('/tmp/a.mp3');
        expect(req, isNotNull);
        expect(req!.path, '/tmp/a.mp3');
        expect(req.bookmark, isNull);
      });

      test('map with path and bookmark returns both', () {
        final req = PlayerPathUtils.coerceOpenRequest({
          'path': '/music/song.mp3',
          'bookmark': 'abc123',
        });
        expect(req, isNotNull);
        expect(req!.path, '/music/song.mp3');
        expect(req.bookmark, 'abc123');
      });

      test('map with empty bookmark returns null bookmark', () {
        final req = PlayerPathUtils.coerceOpenRequest({
          'path': '/music/song.mp3',
          'bookmark': '  ',
        });
        expect(req, isNotNull);
        expect(req!.bookmark, isNull);
      });

      test('map with non-string path returns null', () {
        expect(PlayerPathUtils.coerceOpenRequest({'path': 123}), isNull);
      });
    });

    group('normalizeDropPath', () {
      test('non-file-uri returns trimmed input', () {
        expect(
          PlayerPathUtils.normalizeDropPath(
            '  /path/to/file.mp3  ',
            windows: false,
          ),
          '/path/to/file.mp3',
        );
      });

      test('file uri on unix returns decoded path', () {
        final result = PlayerPathUtils.normalizeDropPath(
          'file:///home/user/music/song.mp3',
          windows: false,
        );
        expect(result, '/home/user/music/song.mp3');
      });

      test('file uri with encoded spaces is decoded', () {
        final result = PlayerPathUtils.normalizeDropPath(
          'file:///home/user/my%20music/song.mp3',
          windows: false,
        );
        expect(result, '/home/user/my music/song.mp3');
      });

      test('file uri on windows returns windows path', () {
        final result = PlayerPathUtils.normalizeDropPath(
          'file:///C:/Users/test/music.mp3',
          windows: true,
        );
        expect(result, contains('C:'));
        expect(result, contains('music.mp3'));
      });

      test('case insensitive file prefix detection', () {
        final result = PlayerPathUtils.normalizeDropPath(
          'FILE:///tmp/a.mp3',
          windows: false,
        );
        expect(result, '/tmp/a.mp3');
      });
    });

    group('extension checks', () {
      test('isAudioExtension recognizes common formats', () {
        for (final ext in ['mp3', 'flac', 'wav', 'ogg', 'aac', 'm4a', 'opus']) {
          expect(PlayerPathUtils.isAudioExtension(ext), isTrue, reason: ext);
        }
      });

      test('isAudioExtension is case insensitive', () {
        expect(PlayerPathUtils.isAudioExtension('MP3'), isTrue);
        expect(PlayerPathUtils.isAudioExtension('Flac'), isTrue);
      });

      test('isAudioExtension rejects video extensions', () {
        expect(PlayerPathUtils.isAudioExtension('mp4'), isFalse);
        expect(PlayerPathUtils.isAudioExtension('mkv'), isFalse);
      });

      test('isSupportedExtension includes audio and video', () {
        expect(PlayerPathUtils.isSupportedExtension('mp3'), isTrue);
        expect(PlayerPathUtils.isSupportedExtension('mp4'), isTrue);
        expect(PlayerPathUtils.isSupportedExtension('mkv'), isTrue);
        expect(PlayerPathUtils.isSupportedExtension('flac'), isTrue);
      });

      test('isSupportedExtension rejects unknown extensions', () {
        expect(PlayerPathUtils.isSupportedExtension('txt'), isFalse);
        expect(PlayerPathUtils.isSupportedExtension('pdf'), isFalse);
        expect(PlayerPathUtils.isSupportedExtension('exe'), isFalse);
      });

      test('audioExtensions and videoExtensions are disjoint', () {
        final overlap = PlayerPathUtils.audioExtensions.intersection(
          PlayerPathUtils.videoExtensions,
        );
        expect(overlap, isEmpty);
      });

      test('supportedExtensions is union of audio and video', () {
        expect(
          PlayerPathUtils.supportedExtensions,
          equals(
            PlayerPathUtils.audioExtensions.union(
              PlayerPathUtils.videoExtensions,
            ),
          ),
        );
      });
    });

    group('isPermissionDeniedError', () {
      test('detects permission denied string', () {
        expect(
          PlayerPathUtils.isPermissionDeniedError(
            Exception('Permission denied'),
          ),
          isTrue,
        );
      });

      test('detects access is denied string', () {
        expect(
          PlayerPathUtils.isPermissionDeniedError(
            Exception('Access is denied'),
          ),
          isTrue,
        );
      });

      test('detects operation not permitted string', () {
        expect(
          PlayerPathUtils.isPermissionDeniedError(
            Exception('Operation not permitted'),
          ),
          isTrue,
        );
      });

      test('detects FileSystemException with error code 13 (EACCES)', () {
        const error = FileSystemException(
          'Cannot open',
          '/tmp/x',
          OSError('Permission denied', 13),
        );
        expect(PlayerPathUtils.isPermissionDeniedError(error), isTrue);
      });

      test(
        'detects FileSystemException with error code 5 (Windows ACCESS_DENIED)',
        () {
          const error = FileSystemException(
            'Cannot open',
            'C:\\x',
            OSError('Access denied', 5),
          );
          expect(PlayerPathUtils.isPermissionDeniedError(error), isTrue);
        },
      );

      test('returns false for unrelated errors', () {
        expect(
          PlayerPathUtils.isPermissionDeniedError(Exception('file not found')),
          isFalse,
        );
      });
    });
  });
}
