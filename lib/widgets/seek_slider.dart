import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../playback/player_controller.dart';
import '../services/seek_preview_service.dart';

class SeekMarker {
  const SeekMarker({required this.position, required this.label});

  final Duration position;
  final String label;
}

class SeekDurationLabel extends StatelessWidget {
  const SeekDurationLabel({
    super.key,
    required this.position,
    required this.duration,
    required this.showRemaining,
    required this.onToggle,
    this.style,
  });

  final Duration position;
  final Duration duration;
  final bool showRemaining;
  final VoidCallback onToggle;
  final TextStyle? style;

  static String format(Duration position, Duration duration, bool remaining) {
    if (!remaining || duration <= Duration.zero) {
      return PlayerController.formatDuration(duration);
    }
    final left = duration - position;
    final clamped = left.isNegative ? Duration.zero : left;
    return '-${PlayerController.formatDuration(clamped)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = showRemaining
        ? l10n.seekDurationToggleShowTotal
        : l10n.seekDurationToggleShowRemaining;
    return Semantics(
      button: true,
      focusable: true,
      label: message,
      excludeSemantics: true,
      onTap: onToggle,
      child: Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              format(position, duration, showRemaining),
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

class SeekSliderWithHover extends StatefulWidget {
  const SeekSliderWithHover({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeekStart,
    required this.onSeekChange,
    required this.onSeekEnd,
    this.previewService,
    this.previewEnabled = false,
    this.markerPositions = const [],
    this.rangeStart,
    this.rangeEnd,
  });

  final Duration position;
  final Duration duration;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final SeekPreviewService? previewService;
  final bool previewEnabled;
  final List<SeekMarker> markerPositions;
  final Duration? rangeStart;
  final Duration? rangeEnd;

  @override
  State<SeekSliderWithHover> createState() => _SeekSliderWithHoverState();
}

class _SeekSliderWithHoverState extends State<SeekSliderWithHover> {
  double? _hoverFraction;
  Uint8List? _previewBytes;
  int _previewRequestId = 0;

  static const double _previewWidth = 200;
  static const double _previewHeight = 112;

  void _maybeRequestPreview(double fraction, double maxMs) {
    final svc = widget.previewService;
    if (!widget.previewEnabled || svc == null || maxMs <= 0) return;
    final target = Duration(milliseconds: (maxMs * fraction).toInt());
    final id = ++_previewRequestId;
    svc.requestPreview(target).then((bytes) {
      if (!mounted || id != _previewRequestId) return;
      if (bytes == null) return;
      setState(() => _previewBytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final showPreview = widget.previewEnabled && _previewBytes != null;
    final positionLabel = PlayerController.formatDuration(widget.position);
    final durationLabel = PlayerController.formatDuration(widget.duration);
    return MergeSemantics(
      child: Semantics(
        slider: true,
        label: AppLocalizations.of(context).semanticsSeekBar,
        value: AppLocalizations.of(context)
            .semanticsSeekBarValue(positionLabel, durationLabel),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (maxMs > 0 &&
                    widget.rangeStart != null &&
                    widget.rangeEnd != null &&
                    widget.rangeEnd! >= widget.rangeStart!)
                  Positioned(
                    left:
                        constraints.maxWidth *
                        (widget.rangeStart!.inMilliseconds / maxMs).clamp(
                          0.0,
                          1.0,
                        ),
                    right:
                        constraints.maxWidth *
                        (1.0 -
                                (widget.rangeEnd!.inMilliseconds / maxMs).clamp(
                                  0.0,
                                  1.0,
                                ))
                            .clamp(0.0, constraints.maxWidth),
                    top: 19,
                    child: IgnorePointer(
                      child: Semantics(
                        container: true,
                        label: AppLocalizations.of(context)
                            .seekLoopRangeSemantics(
                              PlayerController.formatDuration(
                                widget.rangeStart!,
                              ),
                              PlayerController.formatDuration(widget.rangeEnd!),
                            ),
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: 0.44),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (maxMs > 0)
                  for (final marker in widget.markerPositions)
                    Positioned(
                      left:
                          (constraints.maxWidth *
                              (marker.position.inMilliseconds / maxMs).clamp(
                                0.0,
                                1.0,
                              )) -
                          3,
                      top: 15,
                      child: IgnorePointer(
                        child: Semantics(
                          container: true,
                          label: AppLocalizations.of(context)
                              .seekMarkerSemantics(marker.label),
                          child: Container(
                            width: 6,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                MouseRegion(
                  onHover: (e) {
                    final width = constraints.maxWidth;
                    if (width <= 0) return;
                    final fraction = (e.localPosition.dx / width).clamp(
                      0.0,
                      1.0,
                    );
                    setState(() {
                      _hoverFraction = fraction;
                    });
                    _maybeRequestPreview(fraction, maxMs);
                  },
                  onExit: (_) {
                    _previewRequestId++;
                    setState(() {
                      _hoverFraction = null;
                      _previewBytes = null;
                    });
                  },
                  child: Slider(
                    value: widget.position.inMilliseconds.toDouble().clamp(
                      0.0,
                      maxMs,
                    ),
                    max: maxMs,
                    onChangeStart: (_) => widget.onSeekStart(),
                    onChanged: widget.onSeekChange,
                    onChangeEnd: widget.onSeekEnd,
                  ),
                ),
                if (_hoverFraction != null && maxMs > 0)
                  Positioned(
                    left: showPreview
                        ? ((constraints.maxWidth * _hoverFraction!) -
                                  (_previewWidth / 2))
                              .clamp(
                                0.0,
                                math.max(
                                  0.0,
                                  constraints.maxWidth - _previewWidth,
                                ),
                              )
                        : ((constraints.maxWidth * _hoverFraction!) - 28).clamp(
                            0.0,
                            math.max(0.0, constraints.maxWidth - 56),
                          ),
                    top: showPreview ? -(_previewHeight + 34) : -28,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (showPreview)
                            Container(
                              width: _previewWidth,
                              height: _previewHeight,
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.memory(
                                _previewBytes!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                width: _previewWidth,
                                height: _previewHeight,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.74),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              PlayerController.formatDuration(
                                Duration(
                                  milliseconds: (maxMs * _hoverFraction!)
                                      .toInt(),
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
