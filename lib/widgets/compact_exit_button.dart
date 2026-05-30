import 'package:flutter/material.dart';

const _animFastDuration = Duration(milliseconds: 140);

class CompactExitButton extends StatefulWidget {
  const CompactExitButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<CompactExitButton> createState() => _CompactExitButtonState();
}

class _CompactExitButtonState extends State<CompactExitButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Exit mini-player',
      child: Semantics(
        button: true,
        label: 'Exit mini-player',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: _animFastDuration,
              curve: Curves.easeOutCubic,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: _hovering ? 0.72 : 0.48),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: _hovering ? 0.85 : 0.55,
                  ),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close_fullscreen,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
