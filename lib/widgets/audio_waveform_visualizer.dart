import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Spectrum-style visualizer: left = bass/lows, right = treble/highs.
///
/// Simulated (no real FFT yet). Base band shape is seeded per track; live
/// reactivity comes from per-band energy that rises on beat impulses and
/// decays — bass hits harder/slower, treble flickers faster.
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
  static const int _barCount = 64;

  late Ticker _ticker;
  double _phase = 0.0;
  Duration _lastElapsed = Duration.zero;
  late AnimationController _playPauseController;

  final math.Random _random = math.Random();
  // Per-band live energy 0..1 — driven by beat impulses, not a static sine.
  late List<double> _bandEnergy;
  double _nextBeatIn = 0.35;
  double _beatClock = 0.0;

  List<double>? _cachedBase;
  int? _cachedSeed;

  @override
  void initState() {
    super.initState();
    _bandEnergy = List<double>.filled(_barCount, 0.35);
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
              2.2 *
              clampedDt *
              (widget.isPlaying ? 1.0 : _playPauseController.value);
          if (widget.isPlaying) {
            _tickBands(clampedDt);
          } else {
            // Fade energy out on pause.
            for (var i = 0; i < _barCount; i++) {
              _bandEnergy[i] *= math.pow(0.88, clampedDt * 60).toDouble();
            }
          }
        });
      } else {
        _lastElapsed = elapsed;
      }
    })..start();
  }

  void _tickBands(double dt) {
    _beatClock += dt;
    // Decay toward a quiet floor — bass decays slower than treble.
    for (var i = 0; i < _barCount; i++) {
      final t = i / (_barCount - 1);
      final decay = math.pow(0.82 + 0.12 * t, dt * 60).toDouble();
      final floor = 0.12 + 0.08 * (1.0 - t);
      _bandEnergy[i] = floor + (_bandEnergy[i] - floor) * decay;
    }

    // Occasional micro-flutter so bars never look frozen between beats.
    if (_random.nextDouble() < 0.35) {
      final i = _random.nextInt(_barCount);
      final t = i / (_barCount - 1);
      final flutter = (0.04 + 0.10 * t) * _random.nextDouble();
      _bandEnergy[i] = (_bandEnergy[i] + flutter).clamp(0.0, 1.0);
    }

    if (_beatClock < _nextBeatIn) return;
    _beatClock = 0.0;
    // ~90–140 BPM-ish spacing with some swing.
    _nextBeatIn = 0.28 + _random.nextDouble() * 0.32;

    final strength = 0.45 + _random.nextDouble() * 0.55;
    // Kick: left third. Snare/hat: mid/right with lower chance.
    final kind = _random.nextDouble();
    if (kind < 0.55) {
      _impulse(0.0, 0.38, strength, spread: 0.55);
      if (_random.nextDouble() < 0.4) {
        _impulse(0.55, 1.0, strength * 0.35, spread: 0.35);
      }
    } else if (kind < 0.82) {
      _impulse(0.28, 0.62, strength * 0.75, spread: 0.45);
    } else {
      _impulse(0.62, 1.0, strength * 0.55, spread: 0.30);
    }
  }

  void _impulse(
    double fromT,
    double toT,
    double strength, {
    double spread = 0.5,
  }) {
    for (var i = 0; i < _barCount; i++) {
      final t = i / (_barCount - 1);
      if (t < fromT || t > toT) continue;
      final mid = (fromT + toT) / 2;
      final half = math.max(0.001, (toT - fromT) / 2);
      final falloff = 1.0 - ((t - mid).abs() / half) * (1.0 - spread);
      final bump =
          strength *
          falloff.clamp(0.0, 1.0) *
          (0.7 + 0.3 * _random.nextDouble());
      _bandEnergy[i] = (_bandEnergy[i] + bump).clamp(0.0, 1.0);
    }
  }

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _playPauseController.forward();
        _nextBeatIn = 0.05;
        _beatClock = 0.0;
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

  /// Static per-track band envelope: bass tall, treble short.
  List<double> _generateBaseSpectrum(int seed, int count) {
    final random = math.Random(seed);
    final List<double> heights = [];
    double smooth = 0.65;
    for (int i = 0; i < count; i++) {
      final t = i / (count - 1);
      final bandFloor = 0.18 + 0.62 * math.pow(1.0 - t, 1.25).toDouble();
      final bandCeil = (bandFloor + 0.12 + 0.18 * (1.0 - t)).clamp(0.2, 0.95);
      final target = bandFloor + (bandCeil - bandFloor) * random.nextDouble();
      final lerp = 0.55 + 0.25 * t; // treble less correlated
      smooth = smooth * (1.0 - lerp) + target * lerp;
      heights.add(smooth.clamp(0.08, 1.0));
    }
    return heights;
  }

  void _generateBaseIfNeeded() {
    final key = widget.sourceKey ?? '';
    final seed = _getSeed(key, widget.duration);
    if (_cachedBase == null || _cachedSeed != seed) {
      _cachedSeed = seed;
      _cachedBase = _generateBaseSpectrum(seed, _barCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    _generateBaseIfNeeded();

    final base = _cachedBase ?? const <double>[];
    if (base.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.primary.withValues(alpha: 0.18);

    final double progress = widget.duration.inMilliseconds > 0
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    // Combine static envelope with live energy for the frame.
    final heights = List<double>.generate(_barCount, (i) {
      final live = _bandEnergy[i];
      final combined = base[i] * (0.35 + 0.65 * live);
      return combined.clamp(0.06, 1.0);
    });

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
      final t = i / (barCount - 1);
      // Tiny traveling shimmer on top of live energy — keeps motion alive
      // without dominating the beat response.
      final shimmer =
          math.sin(phase * (1.6 + 4.0 * t) + i * 0.4) * 0.04 * playPauseScale;
      final rawHeight = (heights[i] + shimmer).clamp(0.06, 1.0);
      final barHeight =
          rawHeight * totalHeight * 0.88 * (0.25 + 0.75 * playPauseScale);
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
