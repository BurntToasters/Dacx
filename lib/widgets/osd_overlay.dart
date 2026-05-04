import 'dart:async';

import 'package:flutter/material.dart';

/// Lightweight on-screen display overlay for the player.
///
/// Renders the title and current/total time at the top of the surface
/// when the user is interacting (mouse moved, key pressed, transient
/// message). Auto-hides after [autoHide].
class OsdOverlay extends StatefulWidget {
  const OsdOverlay({
    super.key,
    required this.title,
    required this.position,
    required this.duration,
    required this.visible,
    required this.transientMessage,
    this.autoHide = const Duration(seconds: 2),
  });

  final String title;
  final Duration position;
  final Duration duration;
  final bool visible;
  final String? transientMessage;
  final Duration autoHide;

  @override
  State<OsdOverlay> createState() => _OsdOverlayState();
}

class _OsdOverlayState extends State<OsdOverlay> {
  Timer? _hideTimer;
  String? _lastTransient;
  bool _showTransient = false;

  @override
  void didUpdateWidget(covariant OsdOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transientMessage != _lastTransient &&
        widget.transientMessage != null &&
        widget.transientMessage!.isNotEmpty) {
      _lastTransient = widget.transientMessage;
      setState(() => _showTransient = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.autoHide, () {
        if (mounted) setState(() => _showTransient = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final showHeader = widget.visible && widget.title.isNotEmpty;
    final theme = Theme.of(context);

    return IgnorePointer(
      child: Stack(
        children: [
          // Top header: title + time
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: showHeader ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_fmt(widget.position)} / ${_fmt(widget.duration)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Transient message (volume change, mute, screenshot saved...)
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _showTransient ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.transientMessage ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
