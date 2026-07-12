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
}
