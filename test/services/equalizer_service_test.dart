import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/equalizer_service.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('EqualizerService.buildAfChain', () {
    test('returns empty string when all gains are zero', () {
      final chain = EqualizerService.buildAfChain(
        List<double>.filled(SettingsService.eqBandCount, 0),
      );
      expect(chain, isEmpty);
    });

    test('skips gains below the noise epsilon (|g| < 0.05)', () {
      final gains = List<double>.filled(SettingsService.eqBandCount, 0.0);
      gains[0] = 0.04;
      gains[1] = -0.04;
      gains[2] = 0.05;
      final chain = EqualizerService.buildAfChain(gains);
      expect(chain, isNot(contains('f=31')));
      expect(chain, isNot(contains('f=62')));
      expect(chain, contains('f=125'));
    });

    test('clamps gains to the [-12, 12] dB range', () {
      final gains = List<double>.filled(SettingsService.eqBandCount, 0.0);
      gains[0] = 99;
      gains[1] = -99;
      final chain = EqualizerService.buildAfChain(gains);
      expect(chain, contains('g=12.00'));
      expect(chain, contains('g=-12.00'));
    });

    test('emits one lavfi equalizer filter per active band', () {
      final gains = List<double>.filled(SettingsService.eqBandCount, 3.0);
      final chain = EqualizerService.buildAfChain(gains);
      final filters = chain.split(',');
      expect(filters, hasLength(SettingsService.eqBandCount));
      for (final freq in SettingsService.eqBandFrequencies) {
        expect(chain, contains('f=$freq'));
      }
    });

    test('truncates extra gain entries to band count', () {
      final gains = List<double>.filled(SettingsService.eqBandCount + 5, 1.0);
      final chain = EqualizerService.buildAfChain(gains);
      expect(chain.split(',').length, SettingsService.eqBandCount);
    });
  });

  group('EqualizerService.presetById', () {
    test('returns matching preset', () {
      final preset = EqualizerService.presetById('rock');
      expect(preset, isNotNull);
      expect(preset!.label, 'Rock');
      expect(preset.gains, hasLength(SettingsService.eqBandCount));
    });

    test('returns null for unknown id', () {
      expect(EqualizerService.presetById('does-not-exist'), isNull);
    });
  });

  group('EqualizerService.isFlat', () {
    test('true when all gains are within epsilon of zero', () {
      expect(
        EqualizerService.isFlat(
          List<double>.filled(SettingsService.eqBandCount, 0),
        ),
        isTrue,
      );
      expect(
        EqualizerService.isFlat([0.04, -0.04, 0, 0, 0, 0, 0, 0, 0, 0]),
        isTrue,
      );
    });

    test('false when any gain is above epsilon', () {
      expect(
        EqualizerService.isFlat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0.06]),
        isFalse,
      );
    });
  });

  group('kEqPresets catalog', () {
    test('every preset has the expected band count', () {
      for (final p in kEqPresets) {
        expect(
          p.gains,
          hasLength(SettingsService.eqBandCount),
          reason: '${p.id} has wrong band count',
        );
      }
    });

    test('flat preset is, in fact, flat', () {
      final flat = EqualizerService.presetById('flat')!;
      expect(EqualizerService.isFlat(flat.gains), isTrue);
    });
  });

  group('EqState', () {
    test('stores fields verbatim', () {
      const state = EqState(
        enabled: true,
        preset: 'rock',
        gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      expect(state.enabled, isTrue);
      expect(state.preset, 'rock');
      expect(state.gains, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });
  });
}
