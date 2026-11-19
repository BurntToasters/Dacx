import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/compact_exit_button.dart';

const Duration miniOverlayIdleDelay = Duration(seconds: 2);
const Duration _overlayFadeDuration = Duration(milliseconds: 180);
const double _scrimTopHeight = 88;
const double _scrimBottomHeight = 112;

class MiniPlayerLayout extends StatefulWidget {
  const MiniPlayerLayout({
    super.key,
    required this.surface,
    required this.title,
    required this.artist,
    required this.hasMedia,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onExit,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeekStart,
    required this.onSeekChange,
    required this.onSeekEnd,
    required this.onDragWindow,
    this.revealRequests,
    this.onHiddenWithFocus,
  });

  final Widget surface;
  final String title;
  final String? artist;
  final bool hasMedia;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onExit;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onDragWindow;
  final Listenable? revealRequests;
  final VoidCallback? onHiddenWithFocus;

  @override
  State<MiniPlayerLayout> createState() => _MiniPlayerLayoutState();
}

class _MiniPlayerLayoutState extends State<MiniPlayerLayout> {
  Timer? _hideTimer;
  bool _visible = true;
  int _pointersDown = 0;
  final FocusNode _overlayFocus = FocusNode(debugLabel: 'mini-player-overlay');

  @override
  void initState() {
    super.initState();
    widget.revealRequests?.addListener(_reveal);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(MiniPlayerLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealRequests != widget.revealRequests) {
      oldWidget.revealRequests?.removeListener(_reveal);
      widget.revealRequests?.addListener(_reveal);
    }
  }

  @override
  void dispose() {
    widget.revealRequests?.removeListener(_reveal);
    _hideTimer?.cancel();
    _overlayFocus.dispose();
    super.dispose();
  }

  void _reveal() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(miniOverlayIdleDelay, () {
      if (!mounted || _pointersDown > 0 || !_visible) return;
      _hideOverlay();
    });
  }

  void _hideOverlay() {
    final hadFocus = _overlayFocus.hasFocus;
    setState(() => _visible = false);
    if (hadFocus) widget.onHiddenWithFocus?.call();
  }

  void _controlPointerDown() {
    _pointersDown++;
    _reveal();
  }

  void _controlPointerUp() {
    if (_pointersDown > 0) _pointersDown--;
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _reveal(),
      onHover: (_) => _reveal(),
      onExit: (_) => _scheduleHide(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reveal(),
        onPointerMove: (_) => _reveal(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => widget.onDragWindow(),
                child: widget.surface,
              ),
            ),
            Positioned.fill(
              child: Focus(
                focusNode: _overlayFocus,
                canRequestFocus: false,
                skipTraversal: true,
                child: ExcludeFocus(
                  excluding: !_visible,
                  child: IgnorePointer(
                    key: const Key('mini-player-overlay-ignore'),
                    ignoring: !_visible,
                    child: AnimatedOpacity(
                      key: const Key('mini-player-overlay-opacity'),
                      opacity: _visible ? 1 : 0,
                      duration: _overlayFadeDuration,
                      curve: Curves.easeOutCubic,
                      child: _buildOverlay(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _scrimTopHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xA6000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _scrimBottomHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(context)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomBar(context),
        ),
      ],
    );
  }

  Widget _controlListener({required Widget child}) {
    return Listener(
      onPointerDown: (_) => _controlPointerDown(),
      onPointerUp: (_) => _controlPointerUp(),
      onPointerCancel: (_) => _controlPointerUp(),
      child: child,
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final artist = widget.artist;
    const shadows = [Shadow(blurRadius: 4, color: Colors.black54)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _controlListener(child: CompactExitButton(onPressed: widget.onExit)),
          const SizedBox(width: 8),
          Expanded(
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.hasMedia)
                    Text(
                      widget.title,
                      key: const Key('mini-player-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: shadows,
                      ),
                    ),
                  if (widget.hasMedia && artist != null && artist.isNotEmpty)
                    Text(
                      artist,
                      key: const Key('mini-player-artist'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        shadows: shadows,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final canSeek = widget.hasMedia && maxMs > 0;
    final value = canSeek
        ? widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs)
        : 0.0;
    final style = IconButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white30,
      padding: const EdgeInsets.all(6),
      minimumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _controlListener(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('mini-player-prev'),
                  style: style,
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 24,
                  tooltip: l10n.tooltipPreviousTrack,
                  onPressed: widget.hasMedia && widget.canGoPrevious
                      ? widget.onPrevious
                      : null,
                ),
                IconButton(
                  key: const Key('mini-player-play-pause'),
                  style: style,
                  icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
                  iconSize: 32,
                  tooltip: widget.isPlaying
                      ? l10n.actionPause
                      : l10n.actionPlay,
                  onPressed: widget.hasMedia ? widget.onPlayPause : null,
                ),
                IconButton(
                  key: const Key('mini-player-next'),
                  style: style,
                  icon: const Icon(Icons.skip_next),
                  iconSize: 24,
                  tooltip: l10n.tooltipNextTrack,
                  onPressed: widget.hasMedia && widget.canGoNext
                      ? widget.onNext
                      : null,
                ),
              ],
            ),
          ),
          _controlListener(
            child: SizedBox(
              height: 24,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 11,
                  ),
                  disabledActiveTrackColor: Colors.white30,
                  disabledInactiveTrackColor: Colors.white12,
                  disabledThumbColor: Colors.white30,
                ),
                child: Semantics(
                  label: l10n.semanticsSeekBar,
                  child: Slider(
                    key: const Key('mini-player-seek'),
                    min: 0,
                    max: canSeek ? maxMs : 1,
                    value: value,
                    onChangeStart: canSeek ? (_) => widget.onSeekStart() : null,
                    onChanged: canSeek ? widget.onSeekChange : null,
                    onChangeEnd: canSeek ? widget.onSeekEnd : null,
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
