import 'package:dacx/playback/playback_mix_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackMixPolicy', () {
    group('numericAudioIds', () {
      test('filters out auto and no', () {
        final ids = PlaybackMixPolicy.numericAudioIds(['auto', '1', '2', 'no']);
        expect(ids, ['1', '2']);
      });

      test('filters out non-numeric strings', () {
        final ids = PlaybackMixPolicy.numericAudioIds(['1', 'abc', '3']);
        expect(ids, ['1', '3']);
      });

      test('empty input returns empty', () {
        expect(PlaybackMixPolicy.numericAudioIds([]), isEmpty);
      });

      test('preserves order', () {
        final ids = PlaybackMixPolicy.numericAudioIds(['3', '1', '2']);
        expect(ids, ['3', '1', '2']);
      });
    });

    group('numericVideoIds', () {
      test('filters out auto and no', () {
        final ids = PlaybackMixPolicy.numericVideoIds(['auto', '1', 'no']);
        expect(ids, ['1']);
      });

      test('filters out non-numeric strings', () {
        final ids = PlaybackMixPolicy.numericVideoIds(['vid1', '2']);
        expect(ids, ['2']);
      });
    });

    group('buildAudioMixBranch', () {
      test('two tracks produce correct graph', () {
        final graph = PlaybackMixPolicy.buildAudioMixBranch(['1', '2']);
        expect(graph, contains('[aid1]'));
        expect(graph, contains('[aid2]'));
        expect(graph, contains('aformat='));
        expect(graph, contains('amix=inputs=2'));
        expect(graph, contains('[ao]'));
        expect(graph, contains('[a1]'));
        expect(graph, contains('[a2]'));
      });

      test('three tracks produce amix with inputs=3', () {
        final graph = PlaybackMixPolicy.buildAudioMixBranch(['1', '2', '3']);
        expect(graph, contains('amix=inputs=3'));
      });

      test('normalize=0 is set', () {
        final graph = PlaybackMixPolicy.buildAudioMixBranch(['1', '2']);
        expect(graph, contains('normalize=0'));
      });

      test('sample rate is 48000', () {
        final graph = PlaybackMixPolicy.buildAudioMixBranch(['1', '2']);
        expect(graph, contains('sample_rates=48000'));
      });
    });

    group('buildLavfiComplex', () {
      test('audio only (no video) returns audio branch only', () {
        final graph = PlaybackMixPolicy.buildLavfiComplex(
          audioIds: ['1', '2'],
          videoTrackId: null,
        );
        expect(graph, contains('[ao]'));
        expect(graph, isNot(contains('[vo]')));
      });

      test('with video adds null video passthrough', () {
        final graph = PlaybackMixPolicy.buildLavfiComplex(
          audioIds: ['1', '2'],
          videoTrackId: '1',
        );
        expect(graph, contains('[vid1] null [vo]'));
        expect(graph, contains('[ao]'));
      });

      test('empty videoTrackId is treated as no video', () {
        final graph = PlaybackMixPolicy.buildLavfiComplex(
          audioIds: ['1', '2'],
          videoTrackId: '',
        );
        expect(graph, isNot(contains('[vo]')));
      });
    });
  });

  group('PlaybackMixLoadState', () {
    late PlaybackMixLoadState state;

    setUp(() {
      state = PlaybackMixLoadState();
    });

    test('initial state has empty ids and canMix is false', () {
      expect(state.audioIds, isEmpty);
      expect(state.videoIds, isEmpty);
      expect(state.canMix, isFalse);
    });

    test('update filters and stores numeric ids', () {
      state.update(audioIds: ['auto', '1', '2', 'no'], videoIds: ['auto', '1']);
      expect(state.audioIds, ['1', '2']);
      expect(state.videoIds, ['1']);
      expect(state.canMix, isTrue);
    });

    test('single audio track means canMix is false', () {
      state.update(audioIds: ['1'], videoIds: []);
      expect(state.canMix, isFalse);
    });

    test('reset clears state', () {
      state.update(audioIds: ['1', '2'], videoIds: ['1']);
      state.reset();
      expect(state.audioIds, isEmpty);
      expect(state.videoIds, isEmpty);
      expect(state.canMix, isFalse);
    });
  });
}
