import 'package:flutter/material.dart';

enum FullscreenChromeEdge { top, bottom }

const _chromeTransitionDuration = Duration(milliseconds: 180);

class FullscreenChromeOverlay extends StatelessWidget {
  const FullscreenChromeOverlay({
    super.key,
    required this.edge,
    required this.visible,
    required this.onPointerOverChanged,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.child,
  });

  final FullscreenChromeEdge edge;
  final bool visible;
  final ValueChanged<bool> onPointerOverChanged;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hiddenOffset = Offset(0, edge == FullscreenChromeEdge.top ? -1 : 1);
    return IgnorePointer(
      key: const ValueKey('chrome-overlay-ignore'),
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: _chromeTransitionDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          key: const ValueKey('chrome-overlay-opacity'),
          opacity: visible ? 1 : 0,
          duration: _chromeTransitionDuration,
          curve: Curves.easeOutCubic,
          child: MouseRegion(
            onEnter: (_) => onPointerOverChanged(true),
            onExit: (_) => onPointerOverChanged(false),
            child: Listener(
              onPointerDown: (_) => onPointerDown(),
              onPointerUp: (_) => onPointerUp(),
              onPointerCancel: (_) => onPointerUp(),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
