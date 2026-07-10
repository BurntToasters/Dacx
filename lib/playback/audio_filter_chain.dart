import '../services/audio_spectrum_service.dart';
import '../services/equalizer_service.dart';

/// Result of applying a merged mpv audio-filter chain.
class AudioFilterApplyResult {
  const AudioFilterApplyResult({
    required this.appliedChain,
    required this.skipped,
    required this.spectrumInstalled,
    required this.spectrumFailed,
    required this.usedSpectrumFallback,
    required this.failed,
  });

  /// Chain last written to mpv (`''` when cleared).
  final String appliedChain;

  /// True when the requested chain matched [lastAppliedChain].
  final bool skipped;

  final bool spectrumInstalled;
  final bool spectrumFailed;
  final bool usedSpectrumFallback;

  /// True when mpv rejected the chain and no fallback could be applied.
  final bool failed;
}

/// Builds and applies EQ + spectrum `af` chains for mpv.
abstract final class AudioFilterChain {
  static List<String> buildSegments({
    required bool eqEnabled,
    required List<double> eqBands,
    required bool spectrumWanted,
  }) {
    final segments = <String>[];
    if (eqEnabled) {
      final eqChain = EqualizerService.buildAfChain(eqBands);
      if (eqChain.isNotEmpty) segments.add(eqChain);
    }
    if (spectrumWanted) {
      segments.add(AudioSpectrumService.afSegment);
    }
    return segments;
  }

  static String buildMergedChain({
    required bool eqEnabled,
    required List<double> eqBands,
    required bool spectrumWanted,
  }) {
    return buildSegments(
      eqEnabled: eqEnabled,
      eqBands: eqBands,
      spectrumWanted: spectrumWanted,
    ).join(',');
  }

  /// Applies [eqEnabled]/[eqBands]/[spectrumWanted] to mpv via [setAudioFilter].
  ///
  /// When the spectrum segment causes rejection, retries once without it so EQ
  /// can still run (mpv crashes if metadata is polled without a live filter).
  static Future<AudioFilterApplyResult> apply({
    required String? lastAppliedChain,
    required bool eqEnabled,
    required List<double> eqBands,
    required bool spectrumWanted,
    required Future<bool> Function(String filter) setAudioFilter,
  }) async {
    final segments = buildSegments(
      eqEnabled: eqEnabled,
      eqBands: eqBands,
      spectrumWanted: spectrumWanted,
    );
    final merged = segments.join(',');
    if (lastAppliedChain == merged) {
      return AudioFilterApplyResult(
        appliedChain: merged,
        skipped: true,
        spectrumInstalled: false,
        spectrumFailed: false,
        usedSpectrumFallback: false,
        failed: false,
      );
    }

    final ok = await setAudioFilter(merged.isEmpty ? '' : merged);
    if (ok) {
      return AudioFilterApplyResult(
        appliedChain: merged,
        skipped: false,
        spectrumInstalled: spectrumWanted,
        spectrumFailed: false,
        usedSpectrumFallback: false,
        failed: false,
      );
    }

    if (spectrumWanted && segments.length > 1) {
      final fallbackSegments = List<String>.from(segments)..removeLast();
      final fallback = fallbackSegments.join(',');
      final fallbackOk = await setAudioFilter(fallback);
      if (fallbackOk) {
        return AudioFilterApplyResult(
          appliedChain: fallback,
          skipped: false,
          spectrumInstalled: false,
          spectrumFailed: true,
          usedSpectrumFallback: true,
          failed: false,
        );
      }
    }

    return AudioFilterApplyResult(
      appliedChain: lastAppliedChain ?? '',
      skipped: false,
      spectrumInstalled: false,
      spectrumFailed: spectrumWanted,
      usedSpectrumFallback: false,
      failed: true,
    );
  }
}

/// Decides how spectrum polling should react to playback/settings changes.
enum SpectrumSyncAction { startAndApply, stopAndApply, applyOnly }

abstract final class SpectrumSyncPolicy {
  static bool shouldRun({
    required bool playing,
    required bool isAudioFile,
    required bool audioWaveformEnabled,
  }) {
    return playing && isAudioFile && audioWaveformEnabled;
  }

  static SpectrumSyncAction resolve({
    required bool playing,
    required bool isAudioFile,
    required bool audioWaveformEnabled,
    required bool spectrumCurrentlyActive,
  }) {
    final wantsSpectrum = SpectrumSyncPolicy.shouldRun(
      playing: playing,
      isAudioFile: isAudioFile,
      audioWaveformEnabled: audioWaveformEnabled,
    );
    if (wantsSpectrum && !spectrumCurrentlyActive) {
      return SpectrumSyncAction.startAndApply;
    }
    if (!wantsSpectrum && spectrumCurrentlyActive) {
      return SpectrumSyncAction.stopAndApply;
    }
    return SpectrumSyncAction.applyOnly;
  }
}
