import 'package:dacx/playback/track_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTrackLabel', () {
    test('title only', () {
      expect(
        formatTrackLabel(title: 'English', language: null, fallbackId: '1'),
        'English',
      );
    });

    test('language only', () {
      expect(
        formatTrackLabel(title: null, language: 'eng', fallbackId: '1'),
        'eng',
      );
    });

    test('title and language joined with dot separator', () {
      expect(
        formatTrackLabel(title: 'Commentary', language: 'eng', fallbackId: '1'),
        'Commentary \u00b7 eng',
      );
    });

    test('empty title falls back to language', () {
      expect(
        formatTrackLabel(title: '', language: 'jpn', fallbackId: '2'),
        'jpn',
      );
    });

    test('whitespace-only title falls back to language', () {
      expect(
        formatTrackLabel(title: '   ', language: 'fra', fallbackId: '3'),
        'fra',
      );
    });

    test('both null uses default fallback', () {
      expect(
        formatTrackLabel(title: null, language: null, fallbackId: '5'),
        'Track 5',
      );
    });

    test('both empty uses default fallback', () {
      expect(
        formatTrackLabel(title: '', language: '', fallbackId: '7'),
        'Track 7',
      );
    });

    test('custom fallbackLabel overrides default', () {
      expect(
        formatTrackLabel(
          title: null,
          language: null,
          fallbackId: '1',
          fallbackLabel: 'Unknown',
        ),
        'Unknown',
      );
    });

    test('trims whitespace from title and language', () {
      expect(
        formatTrackLabel(
          title: '  Hello  ',
          language: '  eng  ',
          fallbackId: '1',
        ),
        'Hello \u00b7 eng',
      );
    });
  });
}
