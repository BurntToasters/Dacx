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
    this.needsSpectrumConfirm = false,
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

  /// True when spectrum is wanted but not yet confirmed (skip without confirm).
  final bool needsSpectrumConfirm;
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
      segments.addAll(AudioSpectrumService.afSegments);
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

  static bool _chainContainsSpectrum(String chain) =>
      chain.contains('dacxb0') || chain.contains('dacxstats');

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
    bool spectrumCurrentlyConfirmed = false,
  }) async {
    final segments = buildSegments(
      eqEnabled: eqEnabled,
      eqBands: eqBands,
      spectrumWanted: spectrumWanted,
    );
    final merged = segments.join(',');
    if (lastAppliedChain == merged) {
      final needsConfirm =
          spectrumWanted && !spectrumCurrentlyConfirmed && merged.isNotEmpty;
      return AudioFilterApplyResult(
        appliedChain: merged,
        skipped: true,
        spectrumInstalled: spectrumWanted && spectrumCurrentlyConfirmed,
        spectrumFailed: false,
        usedSpectrumFallback: false,
        failed: false,
        needsSpectrumConfirm: needsConfirm,
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
        needsSpectrumConfirm: spectrumWanted,
      );
    }

    if (spectrumWanted) {
      final fallbackSegments = buildSegments(
        eqEnabled: eqEnabled,
        eqBands: eqBands,
        spectrumWanted: false,
      );
      final fallback = fallbackSegments.join(',');
      // Only retry if fallback differs from the failed merge.
      if (fallback != merged) {
        final fallbackOk = await setAudioFilter(
          fallback.isEmpty ? '' : fallback,
        );
        if (fallbackOk) {
          return AudioFilterApplyResult(
            appliedChain: fallback,
            skipped: false,
            spectrumInstalled: false,
            spectrumFailed: true,
            usedSpectrumFallback: true,
            failed: false,
            needsSpectrumConfirm: false,
          );
        }
      } else if (_chainContainsSpectrum(merged)) {
        // spectrum-only chain failed — clear af
        final cleared = await setAudioFilter('');
        if (cleared) {
          return AudioFilterApplyResult(
            appliedChain: '',
            skipped: false,
            spectrumInstalled: false,
            spectrumFailed: true,
            usedSpectrumFallback: true,
            failed: false,
            needsSpectrumConfirm: false,
          );
        }
      }
    }

    return AudioFilterApplyResult(
      appliedChain: lastAppliedChain ?? '',
      skipped: false,
      spectrumInstalled: false,
      spectrumFailed: spectrumWanted,
      usedSpectrumFallback: false,
      failed: true,
      needsSpectrumConfirm: false,
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
    bool multiAudioMixEnabled = false,
  }) {
    // lavfi-complex mix and spectrum af share the audio filter graph and
    // conflict; refuse spectrum while mix is on.
    if (multiAudioMixEnabled) return false;
    return playing && isAudioFile && audioWaveformEnabled;
  }

  static SpectrumSyncAction resolve({
    required bool playing,
    required bool isAudioFile,
    required bool audioWaveformEnabled,
    required bool spectrumCurrentlyActive,
    bool multiAudioMixEnabled = false,
  }) {
    final wantsSpectrum = SpectrumSyncPolicy.shouldRun(
      playing: playing,
      isAudioFile: isAudioFile,
      audioWaveformEnabled: audioWaveformEnabled,
      multiAudioMixEnabled: multiAudioMixEnabled,
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
