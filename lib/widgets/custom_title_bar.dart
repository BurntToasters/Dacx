import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/window_visuals.dart';

/// Custom title bar for Windows and macOS. Returns [SizedBox.shrink] on Linux.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _nativeCaptionVisible = Platform.isWindows;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
    unawaited(_refreshNativeCaptionVisibility());
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_refreshNativeCaptionVisibility());
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
    unawaited(_refreshNativeCaptionVisibility());
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
    unawaited(_refreshNativeCaptionVisibility());
  }

  @override
  void onWindowFocus() => unawaited(_refreshNativeCaptionVisibility());

  @override
  void onWindowRestore() => unawaited(_refreshNativeCaptionVisibility());

  Future<void> _refreshNativeCaptionVisibility() async {
    if (!Platform.isWindows) return;
    try {
      final titleBarHeight = await windowManager.getTitleBarHeight();
      final nativeCaptionVisible = titleBarHeight > 8;
      if (mounted && nativeCaptionVisible != _nativeCaptionVisible) {
        setState(() => _nativeCaptionVisible = nativeCaptionVisible);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if ((!Platform.isWindows && !Platform.isMacOS) ||
        (Platform.isWindows && _nativeCaptionVisible)) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final visuals = context.windowVisuals;
    final isMac = Platform.isMacOS;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visuals.barColor,
          border: Border(bottom: BorderSide(color: visuals.dividerColor)),
        ),
        child: SizedBox(
          height: isMac ? 38 : 32,
          child: Row(
            children: [
              SizedBox(width: isMac ? 72 : 12),
              Icon(
                Icons.play_circle_outline,
                size: 16,
                color: colorScheme.primary.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 8),
              Text(
                'Dacx',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
              if (!isMac) ...[
                _WindowButton(
                  icon: Icons.minimize,
                  onPressed: windowManager.minimize,
                  hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                  iconColor: colorScheme.onSurface.withValues(alpha: 0.78),
                ),
                _WindowButton(
                  icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                  iconSize: _isMaximized ? 14 : 16,
                  onPressed: () async {
                    if (_isMaximized) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  },
                  hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                  iconColor: colorScheme.onSurface.withValues(alpha: 0.78),
                ),
                _WindowButton(
                  icon: Icons.close,
                  onPressed: windowManager.close,
                  hoverColor: Colors.red,
                  hoverIconColor: Colors.white,
                  iconColor: colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color iconColor;
  final Color? hoverIconColor;

  const _WindowButton({
    required this.icon,
    this.iconSize = 16,
    required this.onPressed,
    required this.hoverColor,
    required this.iconColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 32,
          color: _hovering ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              scale: _hovering ? 1.05 : 1.0,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _hovering && widget.hoverIconColor != null
                    ? widget.hoverIconColor
                    : widget.iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
