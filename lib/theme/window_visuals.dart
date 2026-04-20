import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
class WindowVisuals extends ThemeExtension<WindowVisuals> {
  final bool blurEnabled;
  final double blurStrength;
  final Color windowTopColor;
  final Color windowBottomColor;
  final Color barColor;
  final Color contentColor;
  final Color overlayColor;
  final Color borderColor;
  final Color dividerColor;
  final Color shadowColor;
  final Color dragOverlayColor;

  const WindowVisuals({
    required this.blurEnabled,
    required this.blurStrength,
    required this.windowTopColor,
    required this.windowBottomColor,
    required this.barColor,
    required this.contentColor,
    required this.overlayColor,
    required this.borderColor,
    required this.dividerColor,
    required this.shadowColor,
    required this.dragOverlayColor,
  });

  factory WindowVisuals.fromScheme(
    ColorScheme scheme, {
    required bool blurEnabled,
    required double blurStrength,
    double uiOpacity = 1.0,
  }) {
    final strength = blurStrength.clamp(0.0, 1.0).toDouble();
    final opacity = uiOpacity.clamp(0.05, 1.0).toDouble();
    final curvedStrength = Curves.easeOut.transform(strength);
    double withUiOpacity(double alpha) =>
        blurEnabled ? (alpha * opacity).clamp(0.0, 1.0).toDouble() : alpha;
    final shellAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.78, 0.70, curvedStrength)!)
        : 1.0;
    final barAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.72, 0.64, curvedStrength)!)
        : 0.98;
    final contentAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.66, 0.54, curvedStrength)!)
        : 0.98;
    final overlayAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.74, 0.62, curvedStrength)!)
        : 0.99;
    final borderAlpha = blurEnabled ? lerpDouble(0.18, 0.28, strength)! : 0.14;
    final dividerAlpha = blurEnabled ? lerpDouble(0.14, 0.22, strength)! : 0.12;
    final shadowAlpha = blurEnabled ? lerpDouble(0.16, 0.28, strength)! : 0.10;

    final surface = Color.lerp(scheme.surface, scheme.surfaceContainer, 0.35)!;
    final lifted = Color.lerp(surface, scheme.surfaceContainerHighest, 0.62)!;
    final windowTop = Color.lerp(
      surface,
      lifted,
      0.28,
    )!.withValues(alpha: shellAlpha);
    final windowBottom = Color.lerp(surface, scheme.surface, 0.08)!.withValues(
      alpha: blurEnabled
          ? ((shellAlpha + 0.04).clamp(0.0, 1.0)).toDouble()
          : 1.0,
    );
    final bar = Color.lerp(surface, lifted, 0.20)!.withValues(alpha: barAlpha);
    final content = Color.lerp(
      surface,
      lifted,
      0.48,
    )!.withValues(alpha: contentAlpha);
    final overlay = Color.lerp(
      lifted,
      scheme.surface,
      0.18,
    )!.withValues(alpha: overlayAlpha);

    return WindowVisuals(
      blurEnabled: blurEnabled,
      blurStrength: strength,
      windowTopColor: windowTop,
      windowBottomColor: windowBottom,
      barColor: bar,
      contentColor: content,
      overlayColor: overlay,
      borderColor: scheme.outlineVariant.withValues(alpha: borderAlpha),
      dividerColor: scheme.outlineVariant.withValues(alpha: dividerAlpha),
      shadowColor: scheme.shadow.withValues(alpha: shadowAlpha),
      dragOverlayColor: scheme.primary.withValues(
        alpha: blurEnabled ? lerpDouble(0.14, 0.24, strength)! : 0.18,
      ),
    );
  }

  @override
  WindowVisuals copyWith({
    bool? blurEnabled,
    double? blurStrength,
    Color? windowTopColor,
    Color? windowBottomColor,
    Color? barColor,
    Color? contentColor,
    Color? overlayColor,
    Color? borderColor,
    Color? dividerColor,
    Color? shadowColor,
    Color? dragOverlayColor,
  }) {
    return WindowVisuals(
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurStrength: blurStrength ?? this.blurStrength,
      windowTopColor: windowTopColor ?? this.windowTopColor,
      windowBottomColor: windowBottomColor ?? this.windowBottomColor,
      barColor: barColor ?? this.barColor,
      contentColor: contentColor ?? this.contentColor,
      overlayColor: overlayColor ?? this.overlayColor,
      borderColor: borderColor ?? this.borderColor,
      dividerColor: dividerColor ?? this.dividerColor,
      shadowColor: shadowColor ?? this.shadowColor,
      dragOverlayColor: dragOverlayColor ?? this.dragOverlayColor,
    );
  }

  @override
  WindowVisuals lerp(covariant ThemeExtension<WindowVisuals>? other, double t) {
    if (other is! WindowVisuals) return this;
    return WindowVisuals(
      blurEnabled: t < 0.5 ? blurEnabled : other.blurEnabled,
      blurStrength: lerpDouble(blurStrength, other.blurStrength, t)!,
      windowTopColor: Color.lerp(windowTopColor, other.windowTopColor, t)!,
      windowBottomColor: Color.lerp(
        windowBottomColor,
        other.windowBottomColor,
        t,
      )!,
      barColor: Color.lerp(barColor, other.barColor, t)!,
      contentColor: Color.lerp(contentColor, other.contentColor, t)!,
      overlayColor: Color.lerp(overlayColor, other.overlayColor, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      dragOverlayColor: Color.lerp(
        dragOverlayColor,
        other.dragOverlayColor,
        t,
      )!,
    );
  }
}

extension BuildContextWindowVisuals on BuildContext {
  WindowVisuals get windowVisuals => Theme.of(this).extension<WindowVisuals>()!;
}
