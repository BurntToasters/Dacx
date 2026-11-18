import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/window_visuals.dart';

const _animFastDuration = Duration(milliseconds: 140);

class PlayerDragOverlay extends StatelessWidget {
  const PlayerDragOverlay({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: _animFastDuration,
        curve: Curves.easeOutCubic,
        opacity: visible ? 1 : 0,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: ColoredBox(
              color: context.windowVisuals.dragOverlayColor.withValues(
                alpha: 0.28,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_download,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context).dropOverlayHint,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
