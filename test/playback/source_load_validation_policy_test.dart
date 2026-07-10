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

  group('SourceLoadValidationPolicy.validateNormalizedOpen', () {
    test('rejects empty request before file checks', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedOpen(
          source: PlayableSource.file('  '),
          trimmedValue: '',
          normalizedSource: PlayableSource.file(''),
          fileExists: true,
        ).failure,
        SourceLoadValidationFailure.emptySource,
      );
    });

    test('rejects unsupported URLs before file checks', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedOpen(
          source: PlayableSource.url('ftp://example.com/live'),
          trimmedValue: 'ftp://example.com/live',
          normalizedSource: PlayableSource.url('ftp://example.com/live'),
          fileExists: false,
        ).failure,
        SourceLoadValidationFailure.invalidUrl,
      );
    });

    test('rejects missing normalized files after valid request', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedOpen(
          source: PlayableSource.file('/media/missing.mp3'),
          trimmedValue: '/media/missing.mp3',
          normalizedSource: PlayableSource.file('/media/missing.mp3'),
          fileExists: false,
        ).failure,
        SourceLoadValidationFailure.missingFile,
      );
    });

    test('accepts existing files and remote streams', () {
      expect(
        SourceLoadValidationPolicy.validateNormalizedOpen(
          source: PlayableSource.file('/media/song.mp3'),
          trimmedValue: '/media/song.mp3',
          normalizedSource: PlayableSource.file('/media/song.mp3'),
          fileExists: true,
        ).isOk,
        isTrue,
      );
      expect(
        SourceLoadValidationPolicy.validateNormalizedOpen(
          source: PlayableSource.url('https://example.com/live.m3u8'),
          trimmedValue: 'https://example.com/live.m3u8',
          normalizedSource: PlayableSource.url('https://example.com/live.m3u8'),
          fileExists: false,
        ).isOk,
        isTrue,
      );
    });
  });

  group('SourceLoadValidationPolicy.reactionFor', () {
    test('maps empty source to invalid path feedback', () {
      final reaction = SourceLoadValidationPolicy.reactionFor(
        SourceLoadValidationFailure.emptySource,
      );
      expect(reaction.logEvent, 'media_load_invalid_source');
      expect(reaction.shouldPruneRecentFiles, isFalse);
      expect(reaction.userMessage, SourceLoadUserMessageKind.invalidFilePath);
    });

    test('maps missing file to prune and not-found feedback', () {
      final reaction = SourceLoadValidationPolicy.reactionFor(
        SourceLoadValidationFailure.missingFile,
      );
      expect(reaction.logEvent, 'file_load_missing');
      expect(reaction.shouldPruneRecentFiles, isTrue);
      expect(reaction.userMessage, SourceLoadUserMessageKind.fileNotFound);
    });

    test('ok failure kind yields no reaction', () {
      final reaction = SourceLoadValidationPolicy.reactionFor(
        SourceLoadValidationFailure.none,
      );
      expect(reaction.logEvent, isEmpty);
      expect(reaction.userMessage, isNull);
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
      expect(
        SourceLoadFailurePolicy.userMessage(SourceLoadFailureKind.generic),
        SourceLoadUserMessageKind.openFailed,
      );
    });

    test('maps permission failures to user message kind', () {
      expect(
        SourceLoadFailurePolicy.userMessage(
          SourceLoadFailureKind.permissionDenied,
        ),
        SourceLoadUserMessageKind.permissionDenied,
      );
    });
  });
}
