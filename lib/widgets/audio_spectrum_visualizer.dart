import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Real-time audio spectrum visualizer driven by [bandsListenable].
///
/// Band energies are smoothed in [AudioSpectrumService]; this widget paints
/// them and only ticks while paused to decay residual bars.
class AudioSpectrumVisualizer extends StatefulWidget {
  const AudioSpectrumVisualizer({
    super.key,
    required this.isPlaying,
    required this.bandsListenable,
  });

  final bool isPlaying;
  final ValueListenable<List<double>> bandsListenable;

  @override
  State<AudioSpectrumVisualizer> createState() =>
      _AudioSpectrumVisualizerState();
}

class _AudioSpectrumVisualizerState extends State<AudioSpectrumVisualizer>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 32;

  late Ticker _ticker;
  List<double> _displayBands = List<double>.filled(_barCount, 0.0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.bandsListenable.addListener(_onBands);
    _onBands();
  }

  void _onBands() {
    final bands = widget.bandsListenable.value;
    _displayBands = bands.length >= _barCount
        ? List<double>.from(bands.take(_barCount))
        : List<double>.generate(
            _barCount,
            (i) => i < bands.length ? bands[i] : 0.0,
          );
    if (mounted) setState(() {});
    _updateTickerState();
  }

  void _onTick(Duration elapsed) {
    if (widget.isPlaying) return;
    var any = false;
    for (var i = 0; i < _displayBands.length; i++) {
      _displayBands[i] *= 0.86;
      if (_displayBands[i] < 0.004) {
        _displayBands[i] = 0.0;
      } else {
        any = true;
      }
    }
    if (mounted) setState(() {});
    if (!any) _updateTickerState();
  }

  bool _hasEnergy() {
    for (final v in _displayBands) {
      if (v > 0.005) return true;
    }
    return false;
  }

  void _updateTickerState() {
    if (!mounted) return;
    final shouldTick = !widget.isPlaying && _hasEnergy();
    if (shouldTick) {
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  void didUpdateWidget(covariant AudioSpectrumVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bandsListenable != oldWidget.bandsListenable) {
      oldWidget.bandsListenable.removeListener(_onBands);
      widget.bandsListenable.addListener(_onBands);
      _onBands();
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      _updateTickerState();
    }
  }

  @override
  void dispose() {
    widget.bandsListenable.removeListener(_onBands);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpectrumPainter(
          bands: _displayBands,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({required this.bands, required this.color});

  final List<double> bands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final barCount = bands.length;
    final step = size.width / barCount;
    final barWidth = math.max(1.0, step * 0.55);
    final paint = Paint()..color = color;

    for (var i = 0; i < barCount; i++) {
      final rawHeight = bands[i].clamp(0.04, 1.0);
      final barHeight = rawHeight * size.height * 0.88;
      final x = i * step + (step - barWidth) / 2;
      final y = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.bands != bands;
  }
}
