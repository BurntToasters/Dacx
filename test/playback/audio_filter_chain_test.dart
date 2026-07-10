import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/audio_filter_chain.dart';
import 'package:dacx/services/audio_spectrum_service.dart';

void main() {
  group('AudioFilterChain.buildMergedChain', () {
    test('returns empty when EQ off and spectrum not wanted', () {
      expect(
        AudioFilterChain.buildMergedChain(
          eqEnabled: false,
          eqBands: List<double>.filled(10, 0),
          spectrumWanted: false,
        ),
        '',
      );
    });

    test('includes EQ segment when enabled with non-flat bands', () {
      final chain = AudioFilterChain.buildMergedChain(
        eqEnabled: true,
        eqBands: const [6, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        spectrumWanted: false,
      );
      expect(chain, contains('equalizer'));
      expect(chain, isNot(contains('dacxstats')));
    });

    test('includes spectrum segment when wanted', () {
      final chain = AudioFilterChain.buildMergedChain(
        eqEnabled: false,
        eqBands: List<double>.filled(10, 0),
        spectrumWanted: true,
      );
      expect(chain, AudioSpectrumService.afSegment);
    });
  });

  group('AudioFilterChain.apply', () {
    test('skips when chain unchanged', () async {
      var calls = 0;
      final result = await AudioFilterChain.apply(
        lastAppliedChain: '',
        eqEnabled: false,
        eqBands: List<double>.filled(10, 0),
        spectrumWanted: false,
        setAudioFilter: (_) async {
          calls++;
          return true;
        },
      );
      expect(result.skipped, isTrue);
      expect(calls, 0);
    });

    test('applies merged chain and marks spectrum installed', () async {
      String? applied;
      final result = await AudioFilterChain.apply(
        lastAppliedChain: null,
        eqEnabled: false,
        eqBands: List<double>.filled(10, 0),
        spectrumWanted: true,
        setAudioFilter: (filter) async {
          applied = filter;
          return true;
        },
      );
      expect(result.skipped, isFalse);
      expect(result.spectrumInstalled, isTrue);
      expect(applied, AudioSpectrumService.afSegment);
    });

    test('falls back without spectrum when mpv rejects merged chain', () async {
      final calls = <String>[];
      final result = await AudioFilterChain.apply(
        lastAppliedChain: null,
        eqEnabled: true,
        eqBands: const [4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        spectrumWanted: true,
        setAudioFilter: (filter) async {
          calls.add(filter);
          return calls.length > 1;
        },
      );
      expect(calls, hasLength(2));
      expect(calls.first, contains('dacxstats'));
      expect(calls.last, isNot(contains('dacxstats')));
      expect(result.usedSpectrumFallback, isTrue);
      expect(result.spectrumFailed, isTrue);
      expect(result.spectrumInstalled, isFalse);
    });

    test('reports failed when mpv rejects all attempts', () async {
      final result = await AudioFilterChain.apply(
        lastAppliedChain: 'existing',
        eqEnabled: false,
        eqBands: List<double>.filled(10, 0),
        spectrumWanted: true,
        setAudioFilter: (_) async => false,
      );
      expect(result.failed, isTrue);
      expect(result.appliedChain, 'existing');
    });
  });

  group('SpectrumSyncPolicy', () {
    test('shouldRun requires playing audio with visualizer enabled', () {
      expect(
        SpectrumSyncPolicy.shouldRun(
          playing: true,
          isAudioFile: true,
          audioWaveformEnabled: true,
        ),
        isTrue,
      );
      expect(
        SpectrumSyncPolicy.shouldRun(
          playing: false,
          isAudioFile: true,
          audioWaveformEnabled: true,
        ),
        isFalse,
      );
      expect(
        SpectrumSyncPolicy.shouldRun(
          playing: true,
          isAudioFile: false,
          audioWaveformEnabled: true,
        ),
        isFalse,
      );
    });

    test('resolve returns startAndApply when spectrum should start', () {
      expect(
        SpectrumSyncPolicy.resolve(
          playing: true,
          isAudioFile: true,
          audioWaveformEnabled: true,
          spectrumCurrentlyActive: false,
        ),
        SpectrumSyncAction.startAndApply,
      );
    });

    test('resolve returns stopAndApply when spectrum should stop', () {
      expect(
        SpectrumSyncPolicy.resolve(
          playing: false,
          isAudioFile: true,
          audioWaveformEnabled: true,
          spectrumCurrentlyActive: true,
        ),
        SpectrumSyncAction.stopAndApply,
      );
    });

    test('resolve returns applyOnly when state unchanged', () {
      expect(
        SpectrumSyncPolicy.resolve(
          playing: true,
          isAudioFile: true,
          audioWaveformEnabled: true,
          spectrumCurrentlyActive: true,
        ),
        SpectrumSyncAction.applyOnly,
      );
    });
  });
}
