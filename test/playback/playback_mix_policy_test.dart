import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/playback_mix_policy.dart';

void main() {
  test('buildAudioMixBranch wires amix for numeric ids', () {
    final chain = PlaybackMixPolicy.buildAudioMixBranch(['1', '2']);
    expect(chain, contains('[aid1]'));
    expect(chain, contains('[aid2]'));
    expect(chain, contains('amix=inputs=2'));
    expect(chain, endsWith('[ao]'));
  });

  test('buildLavfiComplex prefixes video passthrough when provided', () {
    final chain = PlaybackMixPolicy.buildLavfiComplex(
      audioIds: ['0', '1'],
      videoTrackId: '3',
    );
    expect(chain, startsWith('[vid3] null [vo] ;'));
    expect(chain, contains('amix=inputs=2'));
  });

  test('numericAudioIds filters auto/no and non-numeric', () {
    expect(PlaybackMixPolicy.numericAudioIds(['auto', 'no', '2', 'x', '1']), [
      '2',
      '1',
    ]);
  });
}
