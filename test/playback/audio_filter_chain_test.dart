import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/audio_filter_chain.dart';

void main() {
  group('AudioFilterChain.buildMergedChain', () {
    test('returns empty when EQ off', () {
      expect(
        AudioFilterChain.buildMergedChain(
          eqEnabled: false,
          eqBands: List<double>.filled(10, 0),
        ),
        '',
      );
    });

    test('includes EQ segment when enabled with non-flat bands', () {
      final chain = AudioFilterChain.buildMergedChain(
        eqEnabled: true,
        eqBands: const [6, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(chain, contains('equalizer'));
    });
  });

  group('AudioFilterChain.apply', () {
    test('skips when chain unchanged', () async {
      var calls = 0;
      final result = await AudioFilterChain.apply(
        lastAppliedChain: '',
        eqEnabled: false,
        eqBands: List<double>.filled(10, 0),
        setAudioFilter: (_) async {
          calls++;
          return true;
        },
      );
      expect(result.skipped, isTrue);
      expect(calls, 0);
    });

    test('applies EQ chain when enabled', () async {
      String? applied;
      final result = await AudioFilterChain.apply(
        lastAppliedChain: null,
        eqEnabled: true,
        eqBands: const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        setAudioFilter: (filter) async {
          applied = filter;
          return true;
        },
      );
      expect(result.skipped, isFalse);
      expect(result.failed, isFalse);
      expect(applied, contains('equalizer'));
    });

    test('reports failed when mpv rejects chain', () async {
      final result = await AudioFilterChain.apply(
        lastAppliedChain: 'existing',
        eqEnabled: true,
        eqBands: const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        setAudioFilter: (_) async => false,
      );
      expect(result.failed, isTrue);
      expect(result.appliedChain, 'existing');
    });
  });
}
