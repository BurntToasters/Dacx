import 'dart:ui';

import 'package:flutter/material.dart';

import 'window_visuals.dart';

/// Frosted-glass decoration helpers for blur mode UI.
extension GlassDecorations on WindowVisuals {
  bool get isGlass => blurEnabled;

  /// Window backdrop wash — gradient in glass mode, solid otherwise.
  LinearGradient get shellGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [windowTopColor, windowBottomColor],
    stops: const [0.0, 1.0],
  );

  /// Horizontal chrome (title bar, transport dock).
  BoxDecoration chromeDecoration({
    BorderSide? borderSide,
    bool borderOnTop = false,
  }) {
    final border = borderSide ?? BorderSide(color: dividerColor);
    if (!isGlass) {
      return BoxDecoration(
        color: chromeTopColor,
        border: borderOnTop ? Border(top: border) : Border(bottom: border),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [chromeTopColor, chromeBottomColor],
      ),
      border: borderOnTop ? Border(top: border) : Border(bottom: border),
    );
  }

  /// Elevated card / panel (empty state, audio hero, settings body).
  BoxDecoration panelDecoration({
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(28)),
  }) {
    if (!isGlass) {
      return BoxDecoration(
        borderRadius: borderRadius,
        color: panelTopColor,
        border: Border.all(color: panelBorderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      );
    }
    return BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [panelTopColor, panelBottomColor],
      ),
      border: Border.all(color: panelBorderColor),
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 32,
          offset: const Offset(0, 20),
        ),
        BoxShadow(
          color: rimHighlightColor.withValues(alpha: 0.35),
          blurRadius: 1,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  /// Settings / list scroll surface.
  BoxDecoration overlayDecoration() {
    if (!isGlass) {
      return BoxDecoration(
        color: overlayTopColor,
        border: Border(top: BorderSide(color: dividerColor)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [overlayTopColor, overlayBottomColor],
      ),
      border: Border(top: BorderSide(color: dividerColor)),
    );
  }
}

/// Frosted panel with optional light backdrop blur over native vibrancy.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.maxWidth,
    this.margin,
    this.blurSigma = 10,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double? maxWidth;
  final EdgeInsetsGeometry? margin;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;
    final panel = Container(
      width: maxWidth != null ? double.infinity : null,
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : null,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: visuals.panelDecoration(borderRadius: borderRadius),
      child: child,
    );

    if (!visuals.isGlass || blurSigma <= 0) return panel;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: panel,
      ),
    );
  }
}

/// Title bar / bottom dock chrome strip.
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    super.key,
    required this.child,
    this.height,
    this.borderOnTop = false,
  });

  final Widget child;
  final double? height;
  final bool borderOnTop;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;
    return DecoratedBox(
      decoration: visuals.chromeDecoration(borderOnTop: borderOnTop),
      child: height != null ? SizedBox(height: height, child: child) : child,
    );
  }
}

/// Shell background — gradient in glass mode, solid color otherwise.
class GlassShellBackground extends StatelessWidget {
  const GlassShellBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;
    if (!visuals.isGlass) {
      return DecoratedBox(
        decoration: BoxDecoration(color: visuals.windowBottomColor),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(gradient: visuals.shellGradient),
      child: child,
    );
  }
}

/// Settings / overlay screens — softer wash over window shell.
class GlassOverlayBackground extends StatelessWidget {
  const GlassOverlayBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;
    if (!visuals.isGlass) {
      return DecoratedBox(
        decoration: BoxDecoration(color: visuals.overlayTopColor),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [visuals.overlayTopColor, visuals.windowBottomColor],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted drawer body — used for side-panel drawers (e.g. play queue).
/// Applies backdrop blur in glass mode, solid fill otherwise.
class GlassDrawerBody extends StatelessWidget {
  const GlassDrawerBody({
    super.key,
    required this.child,
    this.borderOnLeft = true,
    this.blurSigma = 12,
  });

  final Widget child;
  final bool borderOnLeft;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final visuals = context.windowVisuals;
    final borderSide = BorderSide(color: visuals.panelBorderColor);

    final body = Container(
      decoration: BoxDecoration(
        color: visuals.isGlass ? null : visuals.panelTopColor,
        gradient: visuals.isGlass
            ? LinearGradient(
                begin: borderOnLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                end: borderOnLeft
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                colors: [visuals.panelTopColor, visuals.panelBottomColor],
              )
            : null,
        border: borderOnLeft
            ? Border(left: borderSide)
            : Border(right: borderSide),
      ),
      child: child,
    );

    if (!visuals.isGlass || blurSigma <= 0) return body;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: body,
      ),
    );
  }
}
