import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AudioWaveformVisualizer extends StatefulWidget {
  const AudioWaveformVisualizer({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.sourceKey,
  });

  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String? sourceKey;

  @override
  State<AudioWaveformVisualizer> createState() =>
      _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  double _phase = 0.0;
  late AnimationController _playPauseController;

  List<double>? _cachedHeights;
  int? _cachedSeed;

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

    _ticker = createTicker((elapsed) {
      if (widget.isPlaying || _playPauseController.value > 0) {
        setState(() {
          // Increment phase smoothly based on elapsed time to drive the bar bounce
          _phase +=
              0.05 * (widget.isPlaying ? 1.0 : _playPauseController.value);
        });
      }
    })..start();
  }

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playPauseController.dispose();
    super.dispose();
  }

  int _getSeed(String key, Duration duration) {
    final str = '${key}_${duration.inMilliseconds}';
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      hash = str.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return hash;
  }

  List<double> _generateWaveform(int seed, int count) {
    final random = math.Random(seed);
    final List<double> heights = [];
    double last = 0.5;
    for (int i = 0; i < count; i++) {
      double target = random.nextDouble();
      // Apply a sine envelope so that start and end fade to look like a complete track waveform
      final progress = i / count;
      final envelope = math.sin(progress * math.pi);
      target = (0.2 + 0.8 * target) * (0.3 + 0.7 * envelope);
      last = last * 0.4 + target * 0.6;
      heights.add(last.clamp(0.05, 1.0));
    }
    return heights;
  }

  void _generateHeightsIfNeeded() {
    final key = widget.sourceKey ?? '';
    final seed = _getSeed(key, widget.duration);
    if (_cachedHeights == null || _cachedSeed != seed) {
      _cachedSeed = seed;
      _cachedHeights = _generateWaveform(seed, 120);
    }
  }

  @override
  Widget build(BuildContext context) {
    _generateHeightsIfNeeded();

    final heights = _cachedHeights ?? const [];
    if (heights.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.primary.withValues(alpha: 0.18);

    final double progress = widget.duration.inMilliseconds > 0
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return RepaintBoundary(
      child: CustomPaint(
        painter: WaveformPainter(
          heights: heights,
          progress: progress,
          phase: _phase,
          playPauseScale: _playPauseController.value,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> heights;
  final double progress;
  final double phase;
  final double playPauseScale;
  final Color activeColor;
  final Color inactiveColor;

  WaveformPainter({
    required this.heights,
    required this.progress,
    required this.phase,
    required this.playPauseScale,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;

    final barCount = heights.length;
    final totalWidth = size.width;
    final totalHeight = size.height;

    final step = totalWidth / barCount;
    final barWidth = (step * 0.6).clamp(1.5, 8.0);

    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (int i = 0; i < barCount; i++) {
      // Oscillate height when playing/pausing
      final bounce = math.sin(phase * 4.0 + i * 0.25) * 0.15 * playPauseScale;
      final rawHeight = (heights[i] + bounce).clamp(0.06, 1.0);

      final barHeight =
          rawHeight *
          totalHeight *
          0.8; // scaling down to avoid hitting top/bottom
      final x = i * step + (step - barWidth) / 2;
      final y = (totalHeight - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      final barCenterX = x + barWidth / 2;
      final isActive = barCenterX <= progress * totalWidth;

      if (isActive) {
        canvas.drawRRect(rect, activePaint);
      } else {
        canvas.drawRRect(rect, inactivePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.playPauseScale != playPauseScale ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.heights != heights;
  }
}
