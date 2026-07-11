import '../services/settings_service.dart';

/// Pure UI policy helpers for [PlayerScreen]. Keeps gating rules testable
/// without initializing libmpv in widget tests.
abstract final class PlayerUiPolicies {
  static bool showSeekPreview({
    required SettingsService settings,
    required bool isAudioFile,
  }) {
    return settings.seekPreviewEnabled && !isAudioFile;
  }

  static bool showAudioSpectrum({
    required SettingsService settings,
    required bool isAudioFile,
  }) {
    if (settings.multiAudioMix) return false;
    return settings.audioWaveformEnabled && isAudioFile;
  }

  static double spectrumHeight(SettingsService settings) {
    if (settings.multiAudioMix) return 0.0;
    return settings.audioWaveformEnabled ? 40.0 : 0.0;
  }
}
