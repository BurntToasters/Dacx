import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Custom title bar for Windows and macOS. Returns [SizedBox.shrink] on Linux.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
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
      child: Container(
        height: isMac ? 38 : 32,
        color: colorScheme.surface,
        child: Row(
          children: [
            // On macOS, leave space for native traffic light buttons.
            SizedBox(width: isMac ? 72 : 12),
            // App icon
            Icon(
              Icons.play_circle_outline,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            // Title
            Text(
              'DACX',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            // Draggable spacer
            const Expanded(child: SizedBox.shrink()),
            // Window buttons (Windows only — macOS uses native traffic lights)
            if (!isMac) ...[
              _WindowButton(
                icon: Icons.minimize,
                onPressed: windowManager.minimize,
                hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              _WindowButton(
                icon: _isMaximized
                    ? Icons.filter_none
                    : Icons.crop_square,
                iconSize: _isMaximized ? 14 : 16,
                onPressed: () async {
                  if (_isMaximized) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              _WindowButton(
                icon: Icons.close,
                onPressed: windowManager.close,
                hoverColor: Colors.red,
                hoverIconColor: Colors.white,
                iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ],
          ],
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
        child: Container(
          width: 46,
          height: 32,
          color: _hovering ? widget.hoverColor : Colors.transparent,
          child: Center(
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
    );
  }
}
