import 'package:flutter/material.dart';

enum FullscreenChromeEdge { top, bottom }

const _chromeTransitionDuration = Duration(milliseconds: 180);

class FullscreenChromeOverlay extends StatefulWidget {
  const FullscreenChromeOverlay({
    super.key,
    required this.edge,
    required this.visible,
    required this.onPointerOverChanged,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.child,
    this.onHiddenWithFocus,
  });

  final FullscreenChromeEdge edge;
  final bool visible;
  final ValueChanged<bool> onPointerOverChanged;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final Widget child;
  final VoidCallback? onHiddenWithFocus;

  @override
  State<FullscreenChromeOverlay> createState() =>
      _FullscreenChromeOverlayState();
}

class _FullscreenChromeOverlayState extends State<FullscreenChromeOverlay> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'fullscreen-chrome');

  @override
  void didUpdateWidget(FullscreenChromeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible && !widget.visible && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onHiddenWithFocus?.call();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible;
    final hiddenOffset = Offset(
      0,
      widget.edge == FullscreenChromeEdge.top ? -1 : 1,
    );
    return ExcludeFocus(
      excluding: !visible,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: false,
        skipTraversal: true,
        child: IgnorePointer(
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
                onEnter: (_) => widget.onPointerOverChanged(true),
                onExit: (_) => widget.onPointerOverChanged(false),
                child: Listener(
                  onPointerDown: (_) => widget.onPointerDown(),
                  onPointerUp: (_) => widget.onPointerUp(),
                  onPointerCancel: (_) => widget.onPointerUp(),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
