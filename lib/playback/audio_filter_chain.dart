import '../services/equalizer_service.dart';

/// Result of applying a merged mpv audio-filter chain.
class AudioFilterApplyResult {
  const AudioFilterApplyResult({
    required this.appliedChain,
    required this.skipped,
    required this.failed,
  });

  /// Chain last written to mpv (`''` when cleared).
  final String appliedChain;

  /// True when the requested chain matched [lastAppliedChain].
  final bool skipped;

  /// True when mpv rejected the chain.
  final bool failed;
}

/// Builds and applies EQ `af` chains for mpv.
abstract final class AudioFilterChain {
  static List<String> buildSegments({
    required bool eqEnabled,
    required List<double> eqBands,
  }) {
    final segments = <String>[];
    if (eqEnabled) {
      final eqChain = EqualizerService.buildAfChain(eqBands);
      if (eqChain.isNotEmpty) segments.add(eqChain);
    }
    return segments;
  }

  static String buildMergedChain({
    required bool eqEnabled,
    required List<double> eqBands,
  }) {
    return buildSegments(eqEnabled: eqEnabled, eqBands: eqBands).join(',');
  }

  /// Applies [eqEnabled]/[eqBands] to mpv via [setAudioFilter].
  static Future<AudioFilterApplyResult> apply({
    required String? lastAppliedChain,
    required bool eqEnabled,
    required List<double> eqBands,
    required Future<bool> Function(String filter) setAudioFilter,
  }) async {
    final segments = buildSegments(eqEnabled: eqEnabled, eqBands: eqBands);
    final merged = segments.join(',');
    if (lastAppliedChain == merged) {
      return AudioFilterApplyResult(
        appliedChain: merged,
        skipped: true,
        failed: false,
      );
    }

    final ok = await setAudioFilter(merged.isEmpty ? '' : merged);
    if (ok) {
      return AudioFilterApplyResult(
        appliedChain: merged,
        skipped: false,
        failed: false,
      );
    }

    return AudioFilterApplyResult(
      appliedChain: lastAppliedChain ?? '',
      skipped: false,
      failed: true,
    );
  }
}
