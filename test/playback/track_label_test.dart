import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/track_label.dart';

void main() {
  test('joins title and language', () {
    expect(
      formatTrackLabel(title: 'Main', language: 'eng', fallbackId: '1'),
      'Main · eng',
    );
  });

  test('falls back to track id', () {
    expect(
      formatTrackLabel(title: null, language: null, fallbackId: '7'),
      'Track 7',
    );
  });
}
