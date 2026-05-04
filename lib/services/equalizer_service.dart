import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

class EqPreset {
  const EqPreset(this.id, this.label, this.gains);
  final String id;
  final String label;
  final List<double> gains;
}

const List<EqPreset> kEqPresets = [
  EqPreset('flat', 'Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset('bass_boost', 'Bass Boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  EqPreset('bass_reduce', 'Bass Reduce', [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
  EqPreset('treble_boost', 'Treble Boost', [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
  EqPreset('vocal', 'Vocal', [-2, -2, -1, 1, 4, 4, 3, 1, 0, -1]),
  EqPreset('rock', 'Rock', [4, 3, -1, -2, -1, 1, 3, 4, 5, 5]),
  EqPreset('electronic', 'Electronic', [4, 3, 0, -2, -2, 0, 1, 2, 4, 5]),
  EqPreset('acoustic', 'Acoustic', [3, 3, 2, 1, 2, 2, 3, 3, 3, 2]),
  EqPreset('loudness', 'Loudness', [5, 4, 0, 0, -2, 0, -1, 4, 5, 4]),
  EqPreset('classical', 'Classical', [3, 2, 1, 0, 0, 0, -2, -3, -3, -4]),
];

class EqualizerService {
  /// Builds an mpv `--af` chain string from band gains.
  /// Uses a chain of `equalizer` filters at the predefined center frequencies.
  static String buildAfChain(List<double> gains) {
    final filters = <String>[];
    for (
      var i = 0;
      i < gains.length && i < SettingsService.eqBandFrequencies.length;
      i++
    ) {
      final g = gains[i].clamp(-12.0, 12.0);
      if (g.abs() < 0.05) continue;
      final f = SettingsService.eqBandFrequencies[i];
      filters.add(
        'lavfi=[equalizer=f=$f:width_type=o:width=2:g=${g.toStringAsFixed(2)}]',
      );
    }
    return filters.join(',');
  }

  static EqPreset? presetById(String id) {
    for (final p in kEqPresets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Returns true if all gains are within an epsilon of zero.
  static bool isFlat(List<double> gains) {
    for (final g in gains) {
      if (g.abs() > 0.05) return false;
    }
    return true;
  }
}

@immutable
class EqState {
  const EqState({
    required this.enabled,
    required this.preset,
    required this.gains,
  });
  final bool enabled;
  final String preset;
  final List<double> gains;
}
