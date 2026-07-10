import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Real-time audio spectrum visualizer driven by [spectrumStream].
///
/// Receives per-band energy values (0–1) from [AudioSpectrumService] and
/// renders them as animated bars. Falls back to gentle idle animation when
/// stream is silent or unavailable.
class AudioSpectrumVisualizer extends StatefulWidget {
  const AudioSpectrumVisualizer({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.spectrumStream,
  });

  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Stream<List<double>> spectrumStream;

  @override
  State<AudioSpectrumVisualizer> createState() =>
      _AudioSpectrumVisualizerState();
}

class _AudioSpectrumVisualizerState extends State<AudioSpectrumVisualizer>
    with TickerProviderStateMixin {
  static const int _barCount = 32;

  late Ticker _ticker;
  late AnimationController _playPauseController;
  Duration _lastElapsed = Duration.zero;

  // Live band data from spectrum service
  List<double> _liveBands = List<double>.filled(_barCount, 0.0);
  // Smoothed display values (with attack/release for visual polish)
  final List<double> _displayBands = List<double>.filled(_barCount, 0.0);

  StreamSubscription<List<double>>? _spectrumSub;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.isPlaying) {
      _playPauseController.value = 1.0;
    }

    _spectrumSub = widget.spectrumStream.listen((bands) {
      _liveBands = bands.length >= _barCount
          ? bands.sublist(0, _barCount)
          : List<double>.generate(
              _barCount,
              (i) => i < bands.length ? bands[i] : 0.0,
            );
      _updateTickerState();
    });

    _ticker = createTicker(_onTick);
    _updateTickerState();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 1.0 / 60.0
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final clampedDt = dt.clamp(0.0, 1.0 / 30.0);

    final scale = widget.isPlaying ? 1.0 : _playPauseController.value;
    if (scale <= 0.001 && !_hasEnergy()) return;

    setState(() {
      for (var i = 0; i < _barCount; i++) {
        final target = _liveBands[i] * scale;
        if (target > _displayBands[i]) {
          // Fast attack
          _displayBands[i] +=
              (target - _displayBands[i]) *
              (1.0 - math.pow(0.08, clampedDt * 60).toDouble());
        } else {
          // Smooth release — bass decays slower
          final t = i / (_barCount - 1);
          final releaseRate = math
              .pow(0.88 + 0.08 * (1.0 - t), clampedDt * 60)
              .toDouble();
          _displayBands[i] = _displayBands[i] * releaseRate;
        }
        _displayBands[i] = _displayBands[i].clamp(0.0, 1.0);
      }
    });

    if (!widget.isPlaying &&
        !_playPauseController.isAnimating &&
        !_hasEnergy()) {
      _updateTickerState();
    }
  }

  bool _hasEnergy() {
    for (final v in _displayBands) {
      if (v > 0.005) return true;
    }
    return false;
  }

  void _updateTickerState() {
    if (!mounted) return;
    final shouldTick =
        widget.isPlaying || _playPauseController.isAnimating || _hasEnergy();
    if (shouldTick) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
      return;
    }
    if (_ticker.isActive) {
      _ticker.stop();
      _lastElapsed = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(covariant AudioSpectrumVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
      _updateTickerState();
    }
    if (widget.spectrumStream != oldWidget.spectrumStream) {
      _spectrumSub?.cancel();
      _spectrumSub = widget.spectrumStream.listen((bands) {
        _liveBands = bands.length >= _barCount
            ? bands.sublist(0, _barCount)
            : List<double>.generate(
                _barCount,
                (i) => i < bands.length ? bands[i] : 0.0,
              );
        _updateTickerState();
      });
    }
  }

  @override
  void dispose() {
    _spectrumSub?.cancel();
    _ticker.dispose();
    _playPauseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.primary.withValues(alpha: 0.18);

    final double progress = widget.duration.inMilliseconds > 0
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpectrumPainter(
          bands: List<double>.from(_displayBands),
          progress: progress,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.bands,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> bands;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final barCount = bands.length;
    final totalWidth = size.width;
    final totalHeight = size.height;
    final step = totalWidth / barCount;
    final barWidth = math.max(1.0, step * 0.55);

    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (int i = 0; i < barCount; i++) {
      final rawHeight = bands[i].clamp(0.04, 1.0);
      final barHeight = rawHeight * totalHeight * 0.88;
      final x = i * step + (step - barWidth) / 2;
      final y = (totalHeight - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      final barCenterX = x + barWidth / 2;
      final isActive = barCenterX <= progress * totalWidth;

      canvas.drawRRect(rect, isActive ? activePaint : inactivePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.bands != bands;
  }
}
