import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/seek_preview_service.dart';

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
  });

  final Duration position;
  final Duration duration;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final SeekPreviewService? previewService;
  final bool previewEnabled;

  @override
  State<SeekSliderWithHover> createState() => _SeekSliderWithHoverState();
}

class _SeekSliderWithHoverState extends State<SeekSliderWithHover> {
  double? _hoverFraction;
  Uint8List? _previewBytes;
  int _previewRequestId = 0;

  static const double _previewWidth = 200;
  static const double _previewHeight = 112;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

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
    final positionLabel = _fmt(widget.position);
    final durationLabel = _fmt(widget.duration);
    return Semantics(
      slider: true,
      label: 'Seek bar',
      value: '$positionLabel of $durationLabel',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              MouseRegion(
                onHover: (e) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  final fraction =
                      (e.localPosition.dx / width).clamp(0.0, 1.0);
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
                  value: widget.position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxMs),
                  max: maxMs,
                  onChangeStart: (_) => widget.onSeekStart(),
                  onChanged: widget.onSeekChange,
                  onChangeEnd: widget.onSeekEnd,
                ),
              ),
              if (_hoverFraction != null && maxMs > 0)
                Positioned(
                  left: showPreview
                      ? (constraints.maxWidth * _hoverFraction!) -
                          (_previewWidth / 2)
                      : (constraints.maxWidth * _hoverFraction!) - 28,
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
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.74),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _fmt(Duration(
                                milliseconds:
                                    (maxMs * _hoverFraction!).toInt())),
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
    );
  }
}
