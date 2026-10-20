import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Settings that drive native window visuals; compared to skip redundant applies.
@immutable
class WindowVisualInputs {
  const WindowVisualInputs({
    required this.themeMode,
    required this.blurEnabled,
    required this.blurStrength,
    required this.opacity,
    required this.experimentalFeatures,
    required this.linuxCompositorBlur,
  });

  factory WindowVisualInputs.fromSettings(SettingsService settings) {
    return WindowVisualInputs(
      themeMode: settings.themeMode,
      blurEnabled: settings.windowBlurEnabled,
      blurStrength: settings.windowBlurStrength,
      opacity: settings.windowOpacity,
      experimentalFeatures: settings.experimentalFeaturesEnabled,
      linuxCompositorBlur: settings.linuxCompositorBlurExperimental,
    );
  }

  final ThemeMode themeMode;
  final bool blurEnabled;
  final double blurStrength;
  final double opacity;
  final bool experimentalFeatures;
  final bool linuxCompositorBlur;

  @override
  bool operator ==(Object other) {
    return other is WindowVisualInputs &&
        other.themeMode == themeMode &&
        other.blurEnabled == blurEnabled &&
        other.blurStrength == blurStrength &&
        other.opacity == opacity &&
        other.experimentalFeatures == experimentalFeatures &&
        other.linuxCompositorBlur == linuxCompositorBlur;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    blurEnabled,
    blurStrength,
    opacity,
    experimentalFeatures,
    linuxCompositorBlur,
  );
}
