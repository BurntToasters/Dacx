import 'package:flutter/material.dart';

import '../../../theme/glass_decorations.dart';
import '../../../theme/window_visuals.dart';

class PlayerCenterPanel extends StatelessWidget {
  const PlayerCenterPanel({
    super.key,
    required this.children,
    this.maxWidth = 560,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassPanel(
        maxWidth: maxWidth,
        padding: const EdgeInsets.fromLTRB(32, 34, 32, 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

class PlayerCenterIconSurface extends StatelessWidget {
  const PlayerCenterIconSurface({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visuals = context.windowVisuals;
    final glass = visuals.isGlass;

    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: glass
            ? RadialGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.20),
                  colorScheme.primary.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: glass ? null : colorScheme.primary.withValues(alpha: 0.14),
        boxShadow: glass
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: glass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    visuals.panelTopColor.withValues(alpha: 0.92),
                    visuals.panelBottomColor.withValues(alpha: 0.88),
                  ],
                )
              : null,
          color: glass ? null : colorScheme.surface.withValues(alpha: 0.52),
          border: Border.all(
            color: glass
                ? visuals.panelBorderColor
                : colorScheme.primary.withValues(alpha: 0.22),
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
