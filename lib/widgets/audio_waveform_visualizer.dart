import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Spectrum-style visualizer: left = bass/lows, right = treble/highs.
///
/// Heights are a seeded fake spectrum (no real FFT yet) with a gentle
/// play-state bounce that keeps bass slower/taller and treble faster/shorter.
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
  Duration _lastElapsed = Duration.zero;
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
        final dt = _lastElapsed == Duration.zero
            ? 1 / 60
            : (elapsed - _lastElapsed).inMicroseconds / 1e6;
        _lastElapsed = elapsed;
        final clampedDt = dt.clamp(0.0, 1 / 30);
        setState(() {
          _phase +=
              1.4 *
              clampedDt *
              (widget.isPlaying ? 1.0 : _playPauseController.value);
        });
      } else {
        _lastElapsed = elapsed;
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

  /// Fake frequency spectrum: bass (left) taller + smoother, treble (right)
  /// shorter + spikier — like a classic media-player EQ visualizer.
  List<double> _generateSpectrum(int seed, int count) {
    final random = math.Random(seed);
    final List<double> heights = [];
    double bassSmooth = 0.7;
    double midSmooth = 0.45;
    double trebleSmooth = 0.25;

    for (int i = 0; i < count; i++) {
      final t = i / (count - 1); // 0 = bass, 1 = treble

      // Log-ish falloff: energy concentrates on the left (lows).
      final bandFloor = 0.12 + 0.78 * math.pow(1.0 - t, 1.35).toDouble();
      final bandCeil = (bandFloor + 0.18 + 0.22 * (1.0 - t)).clamp(0.15, 1.0);

      // Bass: slow correlated motion. Treble: noisier independent spikes.
      final noise = random.nextDouble();
      if (t < 0.33) {
        final target = bandFloor + (bandCeil - bandFloor) * noise;
        bassSmooth = bassSmooth * 0.72 + target * 0.28;
        heights.add(bassSmooth.clamp(0.08, 1.0));
      } else if (t < 0.66) {
        final target = bandFloor + (bandCeil - bandFloor) * noise;
        midSmooth = midSmooth * 0.55 + target * 0.45;
        heights.add(midSmooth.clamp(0.06, 0.92));
      } else {
        final spike = noise > 0.72 ? noise : noise * 0.55;
        final target = bandFloor + (bandCeil - bandFloor) * spike;
        trebleSmooth = trebleSmooth * 0.35 + target * 0.65;
        heights.add(trebleSmooth.clamp(0.05, 0.75));
      }
    }
    return heights;
  }

  void _generateHeightsIfNeeded() {
    final key = widget.sourceKey ?? '';
    final seed = _getSeed(key, widget.duration);
    if (_cachedHeights == null || _cachedSeed != seed) {
      _cachedSeed = seed;
      _cachedHeights = _generateSpectrum(seed, 64);
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
    final barWidth = math.max(1.0, step * 0.55);

    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (int i = 0; i < barCount; i++) {
      final t = i / (barCount - 1); // 0 bass → 1 treble

      // Bass: slow, wide pulse. Treble: faster, smaller shimmer.
      final freq = 1.2 + 5.5 * t;
      final amp = (0.10 - 0.06 * t).clamp(0.03, 0.10);
      final bounce = math.sin(phase * freq + i * 0.35) * amp * playPauseScale;

      final rawHeight = (heights[i] + bounce).clamp(0.06, 1.0);
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
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.playPauseScale != playPauseScale ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.heights != heights;
  }
}
