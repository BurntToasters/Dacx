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

  /// Use [chromeTopColor] instead.
  @Deprecated('Use chromeTopColor / chromeBottomColor')
  final Color barColor;

  /// Use [panelTopColor] instead.
  @Deprecated('Use panelTopColor / panelBottomColor')
  final Color contentColor;

  /// Use [overlayTopColor] instead.
  @Deprecated('Use overlayTopColor / overlayBottomColor')
  final Color overlayColor;

  /// Use [panelBorderColor] instead.
  @Deprecated('Use panelBorderColor')
  final Color borderColor;
  final Color dividerColor;
  final Color shadowColor;
  final Color dragOverlayColor;

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
    // Linear mapping — every 10% of slider produces a visible change.
    double withUiOpacity(double alpha) =>
        blurEnabled ? (alpha * opacity).clamp(0.0, 1.0).toDouble() : alpha;

    // Shell alpha range: 0.82 (low strength = barely frosted) → 0.35 (max
    // strength = very transparent, native blur shows through strongly).
    // Wide range ensures the slider feels responsive end to end.
    final shellAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.82, 0.35, strength)!)
        : 1.0;
    final barAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.85, 0.42, strength)!)
        : 0.98;
    final panelDeepAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.78, 0.32, strength)!)
        : 0.96;
    final overlayAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.84, 0.40, strength)!)
        : 0.99;
    final panelAlpha = blurEnabled
        ? withUiOpacity(lerpDouble(0.88, 0.45, strength)!)
        : 0.98;

    final borderAlpha = blurEnabled ? lerpDouble(0.22, 0.34, strength)! : 0.14;
    final dividerAlpha = blurEnabled ? lerpDouble(0.16, 0.24, strength)! : 0.12;
    final shadowAlpha = blurEnabled ? lerpDouble(0.20, 0.32, strength)! : 0.10;
    final rimAlpha = blurEnabled ? lerpDouble(0.10, 0.18, strength)! : 0.08;

    final isDark = scheme.brightness == Brightness.dark;
    final surface = Color.lerp(scheme.surface, scheme.surfaceContainer, 0.35)!;
    final lifted = Color.lerp(surface, scheme.surfaceContainerHighest, 0.62)!;
    // Subtle accent wash so glass feels cohesive with theme seed.
    final accentWash = Color.lerp(
      surface,
      scheme.primary,
      isDark ? 0.10 : 0.07,
    )!;
    final glassBase = Color.lerp(
      surface,
      accentWash,
      blurEnabled ? 0.55 : 0.0,
    )!;

    final windowTop = Color.lerp(
      glassBase,
      lifted,
      0.22,
    )!.withValues(alpha: shellAlpha);
    final windowBottom = Color.lerp(glassBase, scheme.surface, 0.12)!
        .withValues(
          alpha: blurEnabled
              ? ((shellAlpha + 0.03).clamp(0.0, 1.0)).toDouble()
              : 1.0,
        );

    final chromeTop = Color.lerp(
      glassBase,
      lifted,
      0.30,
    )!.withValues(alpha: barAlpha);
    final chromeBottom = Color.lerp(
      glassBase,
      surface,
      0.18,
    )!.withValues(alpha: (barAlpha * 0.88).clamp(0.0, 1.0));

    final panelTop = Color.lerp(
      lifted,
      glassBase,
      0.15,
    )!.withValues(alpha: panelAlpha);
    final panelBottom = Color.lerp(
      glassBase,
      surface,
      0.25,
    )!.withValues(alpha: panelDeepAlpha);
    final panelBorder = Color.lerp(
      scheme.outlineVariant,
      scheme.primary,
      blurEnabled ? 0.35 : 0.0,
    )!.withValues(alpha: borderAlpha);

    final rimHighlight = (isDark ? Colors.white : scheme.primary).withValues(
      alpha: rimAlpha,
    );

    final overlayTop = Color.lerp(
      lifted,
      glassBase,
      0.10,
    )!.withValues(alpha: overlayAlpha);
    final overlayBottom = Color.lerp(
      glassBase,
      surface,
      0.15,
    )!.withValues(alpha: (overlayAlpha * 0.92).clamp(0.0, 1.0));

    final bar = chromeTop;
    final content = panelTop;
    final overlay = overlayTop;
    final border = panelBorder;
    final divider = scheme.outlineVariant.withValues(alpha: dividerAlpha);

    return WindowVisuals(
      blurEnabled: blurEnabled,
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
      barColor: bar,
      contentColor: content,
      overlayColor: overlay,
      borderColor: border,
      dividerColor: divider,
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
    Color? chromeTopColor,
    Color? chromeBottomColor,
    Color? panelTopColor,
    Color? panelBottomColor,
    Color? panelBorderColor,
    Color? rimHighlightColor,
    Color? overlayTopColor,
    Color? overlayBottomColor,
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
      chromeTopColor: chromeTopColor ?? this.chromeTopColor,
      chromeBottomColor: chromeBottomColor ?? this.chromeBottomColor,
      panelTopColor: panelTopColor ?? this.panelTopColor,
      panelBottomColor: panelBottomColor ?? this.panelBottomColor,
      panelBorderColor: panelBorderColor ?? this.panelBorderColor,
      rimHighlightColor: rimHighlightColor ?? this.rimHighlightColor,
      overlayTopColor: overlayTopColor ?? this.overlayTopColor,
      overlayBottomColor: overlayBottomColor ?? this.overlayBottomColor,
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
  WindowVisuals get windowVisuals =>
      Theme.of(this).extension<WindowVisuals>() ??
      WindowVisuals.fromScheme(
        Theme.of(this).colorScheme,
        blurEnabled: false,
        blurStrength: 0.0,
      );
}
