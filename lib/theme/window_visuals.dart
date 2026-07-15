import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
class WindowVisuals extends ThemeExtension<WindowVisuals> {
  final bool blurEnabled;
  final double blurStrength;
  final Color windowTopColor;
  final Color windowBottomColor;
  final Color chromeTopColor;
  final Color chromeBottomColor;
  final Color panelTopColor;
  final Color panelBottomColor;
  final Color panelBorderColor;
  final Color rimHighlightColor;
  final Color overlayTopColor;
  final Color overlayBottomColor;
  final Color dividerColor;
  final Color shadowColor;
  final Color dragOverlayColor;

  /// Alias for [chromeTopColor] (older call sites).
  Color get barColor => chromeTopColor;

  /// Alias for [panelTopColor] (older call sites).
  Color get contentColor => panelTopColor;

  /// Alias for [overlayTopColor] (older call sites).
  Color get overlayColor => overlayTopColor;

  /// Alias for [panelBorderColor] (older call sites).
  Color get borderColor => panelBorderColor;

  const WindowVisuals({
    required this.blurEnabled,
    required this.blurStrength,
    required this.windowTopColor,
    required this.windowBottomColor,
    required this.chromeTopColor,
    required this.chromeBottomColor,
    required this.panelTopColor,
    required this.panelBottomColor,
    required this.panelBorderColor,
    required this.rimHighlightColor,
    required this.overlayTopColor,
    required this.overlayBottomColor,
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

    // ── Non-blur path: flat opaque colors, no gradients ──────────────
    if (!blurEnabled) {
      final surface = Color.lerp(
        scheme.surface,
        scheme.surfaceContainer,
        0.35,
      )!;
      final lifted = Color.lerp(surface, scheme.surfaceContainerHighest, 0.62)!;
      final bar = Color.lerp(surface, lifted, 0.20)!;
      final content = Color.lerp(surface, lifted, 0.48)!;
      final overlay = Color.lerp(lifted, scheme.surface, 0.18)!;
      final border = scheme.outlineVariant.withValues(alpha: 0.14);
      final divider = scheme.outlineVariant.withValues(alpha: 0.12);
      final shadow = scheme.shadow.withValues(alpha: 0.10);

      return WindowVisuals(
        blurEnabled: false,
        blurStrength: strength,
        windowTopColor: Color.lerp(surface, lifted, 0.28)!,
        windowBottomColor: Color.lerp(surface, scheme.surface, 0.08)!,
        chromeTopColor: bar,
        chromeBottomColor: bar,
        panelTopColor: content,
        panelBottomColor: content,
        panelBorderColor: border,
        rimHighlightColor: Colors.transparent,
        overlayTopColor: overlay,
        overlayBottomColor: overlay,
        dividerColor: divider,
        shadowColor: shadow,
        dragOverlayColor: scheme.primary.withValues(alpha: 0.18),
      );
    }

    // ── Glass / blur path: gradients, accent wash, transparency ──────
    final opacity = uiOpacity.clamp(0.05, 1.0).toDouble();
    double withUiOpacity(double alpha) =>
        (alpha * opacity).clamp(0.0, 1.0).toDouble();

    // Shell alpha range: 0.82 (low strength = barely frosted) → 0.35 (max
    // strength = very transparent, native blur shows through strongly).
    final shellAlpha = withUiOpacity(lerpDouble(0.82, 0.35, strength)!);
    final barAlpha = withUiOpacity(lerpDouble(0.85, 0.42, strength)!);
    final panelDeepAlpha = withUiOpacity(lerpDouble(0.78, 0.32, strength)!);
    final overlayAlpha = withUiOpacity(lerpDouble(0.84, 0.40, strength)!);
    final panelAlpha = withUiOpacity(lerpDouble(0.88, 0.45, strength)!);

    final borderAlpha = lerpDouble(0.22, 0.34, strength)!;
    final shadowAlpha = lerpDouble(0.18, 0.32, strength)!;

    final surface = scheme.surface;
    final lifted = Color.lerp(surface, scheme.surfaceContainerHighest, 0.55)!;
    final accentWash = Color.lerp(surface, scheme.primaryContainer, 0.18)!;

    final windowTop = Color.lerp(
      accentWash,
      lifted,
      0.35,
    )!.withValues(alpha: shellAlpha);
    final windowBottom = Color.lerp(
      surface,
      accentWash,
      0.12,
    )!.withValues(alpha: shellAlpha * 0.92);
    final chromeTop = Color.lerp(
      lifted,
      accentWash,
      0.22,
    )!.withValues(alpha: barAlpha);
    final chromeBottom = Color.lerp(
      surface,
      lifted,
      0.40,
    )!.withValues(alpha: barAlpha * 0.95);
    final panelTop = Color.lerp(
      lifted,
      surface,
      0.15,
    )!.withValues(alpha: panelAlpha);
    final panelBottom = Color.lerp(
      surface,
      lifted,
      0.25,
    )!.withValues(alpha: panelDeepAlpha);
    final overlayTop = Color.lerp(
      lifted,
      accentWash,
      0.10,
    )!.withValues(alpha: overlayAlpha);
    final overlayBottom = Color.lerp(
      surface,
      lifted,
      0.20,
    )!.withValues(alpha: overlayAlpha * 0.96);
    final panelBorder = scheme.outlineVariant.withValues(alpha: borderAlpha);
    final rimHighlight = Colors.white.withValues(
      alpha: lerpDouble(0.06, 0.14, strength)!,
    );
    final divider = scheme.outlineVariant.withValues(
      alpha: lerpDouble(0.10, 0.18, strength)!,
    );

    return WindowVisuals(
      blurEnabled: true,
      blurStrength: strength,
      windowTopColor: windowTop,
      windowBottomColor: windowBottom,
      chromeTopColor: chromeTop,
      chromeBottomColor: chromeBottom,
      panelTopColor: panelTop,
      panelBottomColor: panelBottom,
      panelBorderColor: panelBorder,
      rimHighlightColor: rimHighlight,
      overlayTopColor: overlayTop,
      overlayBottomColor: overlayBottom,
      dividerColor: divider,
      shadowColor: scheme.shadow.withValues(alpha: shadowAlpha),
      dragOverlayColor: scheme.primary.withValues(
        alpha: lerpDouble(0.14, 0.24, strength)!,
      ),
    );
  }

  @override
  WindowVisuals copyWith({
    bool? blurEnabled,
    double? blurStrength,
    Color? windowTopColor,
    Color? windowBottomColor,
    Color? chromeTopColor,
    Color? chromeBottomColor,
    Color? panelTopColor,
    Color? panelBottomColor,
    Color? panelBorderColor,
    Color? rimHighlightColor,
    Color? overlayTopColor,
    Color? overlayBottomColor,
    Color? dividerColor,
    Color? shadowColor,
    Color? dragOverlayColor,
  }) {
    return WindowVisuals(
      blurEnabled: blurEnabled ?? this.blurEnabled,
      blurStrength: blurStrength ?? this.blurStrength,
      windowTopColor: windowTopColor ?? this.windowTopColor,
      windowBottomColor: windowBottomColor ?? this.windowBottomColor,
      chromeTopColor: chromeTopColor ?? this.chromeTopColor,
      chromeBottomColor: chromeBottomColor ?? this.chromeBottomColor,
      panelTopColor: panelTopColor ?? this.panelTopColor,
      panelBottomColor: panelBottomColor ?? this.panelBottomColor,
      panelBorderColor: panelBorderColor ?? this.panelBorderColor,
      rimHighlightColor: rimHighlightColor ?? this.rimHighlightColor,
      overlayTopColor: overlayTopColor ?? this.overlayTopColor,
      overlayBottomColor: overlayBottomColor ?? this.overlayBottomColor,
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
      chromeTopColor: Color.lerp(chromeTopColor, other.chromeTopColor, t)!,
      chromeBottomColor: Color.lerp(
        chromeBottomColor,
        other.chromeBottomColor,
        t,
      )!,
      panelTopColor: Color.lerp(panelTopColor, other.panelTopColor, t)!,
      panelBottomColor: Color.lerp(
        panelBottomColor,
        other.panelBottomColor,
        t,
      )!,
      panelBorderColor: Color.lerp(
        panelBorderColor,
        other.panelBorderColor,
        t,
      )!,
      rimHighlightColor: Color.lerp(
        rimHighlightColor,
        other.rimHighlightColor,
        t,
      )!,
      overlayTopColor: Color.lerp(overlayTopColor, other.overlayTopColor, t)!,
      overlayBottomColor: Color.lerp(
        overlayBottomColor,
        other.overlayBottomColor,
        t,
      )!,
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
  WindowVisuals get windowVisuals =>
      Theme.of(this).extension<WindowVisuals>() ??
      WindowVisuals.fromScheme(
        Theme.of(this).colorScheme,
        blurEnabled: false,
        blurStrength: 0.0,
      );
}
