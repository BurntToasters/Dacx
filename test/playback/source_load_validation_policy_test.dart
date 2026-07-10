import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/source_load_validation_policy.dart';

void main() {
  group('SourceLoadValidationPolicy.validateRequest', () {
    test('rejects empty trimmed values', () {
      expect(
        SourceLoadValidationPolicy.validateRequest(
          source: PlayableSource.file('  '),
          trimmedValue: '',
        ).failure,
        SourceLoadValidationFailure.emptySource,
      );
    });

    test('rejects unsupported stream URLs', () {
      expect(
        SourceLoadValidationPolicy.validateRequest(
          source: PlayableSource.url('ftp://example.com/live'),
          trimmedValue: 'ftp://example.com/live',
        ).failure,
        SourceLoadValidationFailure.invalidUrl,
      );
    });

    test('accepts valid file and http(s) requests', () {
      expect(
        SourceLoadValidationPolicy.validateRequest(
          source: PlayableSource.file('/media/song.mp3'),
          trimmedValue: '/media/song.mp3',
        ).isOk,
        isTrue,
      );
      expect(
        SourceLoadValidationPolicy.validateRequest(
          source: PlayableSource.url('https://example.com/live.m3u8'),
          trimmedValue: 'https://example.com/live.m3u8',
        ).isOk,
        isTrue,
      );
    });
  });

  group('SourceLoadValidationPolicy.validateNormalizedFile', () {
    test('rejects missing local files after normalization', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedFile(
          isFile: true,
          fileExists: false,
        ).failure,
        SourceLoadValidationFailure.missingFile,
      );
    });

    test('accepts existing files and remote streams', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedFile(
          isFile: true,
          fileExists: true,
        ).isOk,
        isTrue,
      );
      expect(
        SourceLoadValidationPolicy.validateNormalizedFile(
          isFile: false,
          fileExists: false,
        ).isOk,
        isTrue,
      );
    });
  });

  group('SourceLoadFailurePolicy', () {
    test('classifies permission errors', () {
      expect(
        SourceLoadFailurePolicy.classify(
          Exception('open failed: Permission denied'),
        ),
        SourceLoadFailureKind.permissionDenied,
      );
      expect(
        SourceLoadFailurePolicy.logEvent(
          SourceLoadFailureKind.permissionDenied,
        ),
        'file_load_permission_denied',
      );
    });

    test('classifies generic failures', () {
      expect(
        SourceLoadFailurePolicy.classify(Exception('decoder failed')),
        SourceLoadFailureKind.generic,
      );
      expect(
        SourceLoadFailurePolicy.logEvent(SourceLoadFailureKind.generic),
        'file_load_failed',
      );
    });
  });
}
