import 'package:dacx/services/equalizer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EqualizerService', () {
    group('buildAfChain', () {
      test('flat gains produce empty chain', () {
        final chain = EqualizerService.buildAfChain([
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(chain, isEmpty);
      });

      test('single non-zero gain produces one filter', () {
        final chain = EqualizerService.buildAfChain([
          6,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(chain, contains('equalizer=f=31'));
        expect(chain, contains('g=6.00'));
        expect(chain.split(',').length, 1);
      });

      test('multiple non-zero gains produce comma-separated filters', () {
        final chain = EqualizerService.buildAfChain([
          3,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          -4,
        ]);
        final parts = chain.split(',');
        expect(parts.length, 2);
        expect(parts[0], contains('f=31'));
        expect(parts[0], contains('g=3.00'));
        expect(parts[1], contains('f=16000'));
        expect(parts[1], contains('g=-4.00'));
      });

      test('gains are clamped to -12..12', () {
        final chain = EqualizerService.buildAfChain([
          20,
          -20,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(chain, contains('g=12.00'));
        expect(chain, contains('g=-12.00'));
      });

      test('very small gains below 0.05 are treated as zero', () {
        final chain = EqualizerService.buildAfChain([
          0.04,
          -0.03,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(chain, isEmpty);
      });

      test('each filter uses lavfi format with width_type=o', () {
        final chain = EqualizerService.buildAfChain([
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(chain, contains('lavfi=[equalizer='));
        expect(chain, contains('width_type=o'));
        expect(chain, contains('width=2'));
      });

      test('empty gains list produces empty chain', () {
        final chain = EqualizerService.buildAfChain([]);
        expect(chain, isEmpty);
      });

      test('extra gains beyond 10 bands are ignored', () {
        final chain = EqualizerService.buildAfChain([
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
        ]);
        // Should only produce filters for the 10 defined frequency bands
        final parts = chain.split(',');
        expect(parts.length, 10);
      });
    });

    group('presetById', () {
      test('returns matching preset', () {
        final preset = EqualizerService.presetById('bass_boost');
        expect(preset, isNotNull);
        expect(preset!.id, 'bass_boost');
        expect(preset.gains.length, 10);
        expect(preset.gains[0], 6);
      });

      test('returns null for unknown id', () {
        expect(EqualizerService.presetById('nonexistent'), isNull);
      });

      test('flat preset has all zeros', () {
        final flat = EqualizerService.presetById('flat');
        expect(flat, isNotNull);
        expect(flat!.gains, everyElement(0));
      });
    });

    group('isFlat', () {
      test('all zeros is flat', () {
        expect(EqualizerService.isFlat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), isTrue);
      });

      test('values within epsilon of zero are flat', () {
        expect(
          EqualizerService.isFlat([0.04, -0.04, 0.01, 0, 0, 0, 0, 0, 0, 0]),
          isTrue,
        );
      });

      test('any value above epsilon is not flat', () {
        expect(
          EqualizerService.isFlat([0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0]),
          isFalse,
        );
      });

      test('negative values above epsilon are not flat', () {
        expect(
          EqualizerService.isFlat([0, 0, 0, -1, 0, 0, 0, 0, 0, 0]),
          isFalse,
        );
      });

      test('empty list is flat', () {
        expect(EqualizerService.isFlat([]), isTrue);
      });
    });

    group('kEqPresets', () {
      test('all presets have 10 bands', () {
        for (final preset in kEqPresets) {
          expect(
            preset.gains.length,
            10,
            reason: '${preset.id} should have 10 bands',
          );
        }
      });

      test('all presets have non-empty id and label', () {
        for (final preset in kEqPresets) {
          expect(preset.id, isNotEmpty);
          expect(preset.label, isNotEmpty);
        }
      });

      test('preset ids are unique', () {
        final ids = kEqPresets.map((p) => p.id).toSet();
        expect(ids.length, kEqPresets.length);
      });
    });

    group('EqState', () {
      test('stores fields correctly', () {
        final state = EqState(
          enabled: true,
          preset: 'rock',
          gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        );
        expect(state.enabled, isTrue);
        expect(state.preset, 'rock');
        expect(state.gains.length, 10);
      });
    });
  });
}
