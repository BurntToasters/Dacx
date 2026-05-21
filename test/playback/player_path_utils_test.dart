import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/player_path_utils.dart';

void main() {
  group('PlayerPathUtils.coerceOpenPath', () {
    test('returns trimmed string paths', () {
      expect(PlayerPathUtils.coerceOpenPath('  /a/b.mp3  '), '/a/b.mp3');
    });

    test('rejects non-strings and empty values', () {
      expect(PlayerPathUtils.coerceOpenPath(42), isNull);
      expect(PlayerPathUtils.coerceOpenPath(''), isNull);
      expect(PlayerPathUtils.coerceOpenPath('   '), isNull);
    });
  });

  group('PlayerPathUtils.normalizeDropPath', () {
    test('decodes file URI on Windows', () {
      final path = PlayerPathUtils.normalizeDropPath(
        'file:///C:/music/song.mp3',
        windows: true,
      );
      expect(path.toLowerCase(), contains('song.mp3'));
    });

    test('returns raw path when not a file URI', () {
      expect(
        PlayerPathUtils.normalizeDropPath('/tmp/a.flac', windows: false),
        '/tmp/a.flac',
      );
    });
  });

  group('PlayerPathUtils.isPermissionDeniedError', () {
    test('detects permission denied message', () {
      expect(
        PlayerPathUtils.isPermissionDeniedError(
          Exception('Permission denied'),
        ),
        isTrue,
      );
    });

    test('detects FileSystemException codes', () {
      expect(
        PlayerPathUtils.isPermissionDeniedError(
          const FileSystemException('', '', OSError('denied', 13)),
        ),
        isTrue,
      );
    });

    test('returns false for unrelated errors', () {
      expect(
        PlayerPathUtils.isPermissionDeniedError(Exception('network down')),
        isFalse,
      );
    });
  });

  group('PlayerPathUtils extensions', () {
    test('classifies audio and supported extensions', () {
      expect(PlayerPathUtils.isAudioExtension('flac'), isTrue);
      expect(PlayerPathUtils.isSupportedExtension('mkv'), isTrue);
      expect(PlayerPathUtils.isSupportedExtension('txt'), isFalse);
    });
  });
}
