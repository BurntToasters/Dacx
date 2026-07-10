import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'player_service.dart';

/// Polls RMS/Peak energy metadata from mpv's `astats` audio filter and
/// distributes the energy across [bandCount] frequency-weighted bands for
/// visualization.
///
/// Uses a simple `astats` lavfi filter with metadata output — no crossover
/// splitting or complex graph. The single RMS/Peak measurement is shaped
/// into a pseudo-spectrum using frequency weighting and smoothing.
class AudioSpectrumService {
  AudioSpectrumService({
    required PlayerService playerService,
    this.bandCount = 32,
    this.pollInterval = const Duration(milliseconds: 50),
  }) : _playerService = playerService;

  final PlayerService _playerService;
  final int bandCount;
  final Duration pollInterval;

  Timer? _pollTimer;
  bool _active = false;
  bool _filterInstalled = false;
  int _pollSession = 0;
  bool _pollInFlight = false;

  // Current state
  late final List<double> _bandEnergy = List<double>.filled(bandCount, 0.0);
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  /// Stream of per-band energy values (0.0–1.0), emitted at poll rate.
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  /// Current band energies (for synchronous read).
  List<double> get currentSpectrum => _bandEnergy;

  bool get isActive => _active;

  /// Whether the af filter was confirmed installed by mpv.
  bool get isFilterInstalled => _filterInstalled;

  /// The af filter segment this service needs appended to the chain.
  /// Simple astats with metadata enabled — lightweight and universally supported.
  static const String _afLabel = 'dacxstats';
  static const double _dbFloor = -60.0;
  static const String afSegment =
      '@$_afLabel:lavfi=[astats=metadata=1:reset=1:measure_perchannel=RMS_level+Peak_level:measure_overall=RMS_level+Peak_level]';

  // Property paths for the simple astats filter.
  static const String _rmsProperty =
      'af-metadata/$_afLabel/lavfi.astats.Overall.RMS_level';
  static const String _peakProperty =
      'af-metadata/$_afLabel/lavfi.astats.Overall.Peak_level';
  // Per-channel paths (stereo: channels 1 & 2)
  static const String _rmsLeftProperty =
      'af-metadata/$_afLabel/lavfi.astats.1.RMS_level';
  static const String _rmsRightProperty =
      'af-metadata/$_afLabel/lavfi.astats.2.RMS_level';

  /// Start polling. Call after playback begins.
  /// Does NOT start the poll timer until [confirmFilterInstalled] is called.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _filterInstalled = false;
    _pollSession++;
    _resetBands();
  }

  /// Called by the caller after verifying the merged af chain was accepted
  /// by mpv (i.e. `setAudioFilter` returned true). Only then is it safe to
  /// poll `af-metadata` without risking a native crash.
  void confirmFilterInstalled() {
    if (!_active) return;
    _filterInstalled = true;
    _pollTimer?.cancel();
    final session = _pollSession;
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick(session));
  }

  /// Called when the filter chain was rejected by mpv.
  /// Prevents polling and avoids native crashes.
  void confirmFilterFailed() {
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Stop polling and reset state.
  Future<void> stop() async {
    _pollSession++;
    _active = false;
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _resetBands();
    if (!_spectrumController.isClosed) {
      _spectrumController.add(List<double>.from(_bandEnergy));
    }
  }

  /// Must be called when af chain is rebuilt (e.g. EQ toggled).
  void markFilterDirty() {
    // Caller manages af chain rebuild; this pauses polling until
    // confirmFilterInstalled is called again.
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Polling ────────────────────────────────────────────────

  Future<void> _pollTick(int session) async {
    if (!_active ||
        !_filterInstalled ||
        _playerService.isDisposed ||
        session != _pollSession) {
      return;
    }
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      await _pollOnce();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioSpectrumService poll error: $e');
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _pollOnce() async {
    if (!_active || !_filterInstalled || _playerService.isDisposed) return;

    // Read overall RMS + Peak (most reliable)
    final rmsStr = await _playerService.getProperty(_rmsProperty);
    final peakStr = await _playerService.getProperty(_peakProperty);

    // Also try per-channel for stereo spread
    final rmsLeftStr = await _playerService.getProperty(_rmsLeftProperty);
    final rmsRightStr = await _playerService.getProperty(_rmsRightProperty);

    final rms = _parseDb(rmsStr);
    final peak = _parseDb(peakStr);
    final rmsLeft = _parseDb(rmsLeftStr);
    final rmsRight = _parseDb(rmsRightStr);

    // If we got nothing at all, the filter may not be producing metadata yet.
    if (rms == null && peak == null && rmsLeft == null && rmsRight == null) {
      return;
    }

    final overallDb = math.max(rms ?? _dbFloor, peak ?? _dbFloor);
    final leftDb = rmsLeft ?? overallDb;
    final rightDb = rmsRight ?? overallDb;

    _distributeEnergy(overallDb, leftDb, rightDb);
  }

  /// Distributes overall + stereo energy across [bandCount] bands with
  /// frequency weighting and smoothing to create a plausible spectrum shape.
  void _distributeEnergy(double overallDb, double leftDb, double rightDb) {
    final overallEnergy = _dbToLinear(overallDb);
    final leftEnergy = _dbToLinear(leftDb);
    final rightEnergy = _dbToLinear(rightDb);
    final stereoSpread = (leftEnergy - rightEnergy).abs();

    for (var i = 0; i < bandCount; i++) {
      final position = bandCount <= 1 ? 0.5 : i / (bandCount - 1);

      // Shape factor: bass bands get more energy, treble less, mid stays neutral.
      // This creates a natural-looking frequency distribution.
      final bassWeight = math.pow(1.0 - position, 1.6).toDouble();
      final trebleWeight = math.pow(position, 2.2).toDouble();
      final midWeight = math
          .sin(position * math.pi)
          .toDouble(); // peak at center

      // Combine: overall provides the base, with bass/treble shaping
      final shaped =
          overallEnergy *
          (0.55 + 0.30 * bassWeight + 0.15 * midWeight - 0.08 * trebleWeight);

      // Add stereo variation: left-heavy signals boost low bands, right boosts high
      final stereoOffset =
          stereoSpread * 0.12 * (position < 0.5 ? leftEnergy : rightEnergy);

      final target = (shaped + stereoOffset).clamp(0.0, 1.0);

      // Smooth with attack/release (faster attack for high bands, slower release for low)
      final attackRate = 0.50 + 0.35 * position;
      final releaseRate = 0.82 + 0.12 * (1.0 - position);

      if (target > _bandEnergy[i]) {
        _bandEnergy[i] =
            _bandEnergy[i] * (1.0 - attackRate) + target * attackRate;
      } else {
        _bandEnergy[i] =
            _bandEnergy[i] * releaseRate + target * (1.0 - releaseRate);
      }
      _bandEnergy[i] = _bandEnergy[i].clamp(0.0, 1.0);
    }

    if (!_spectrumController.isClosed) {
      _spectrumController.add(List<double>.from(_bandEnergy));
    }
  }

  // ── Helpers ────────────────────────────────────────────────

  /// Reset all band energies to zero (e.g. on seek or source change).
  void resetDynamics() => _resetBands();

  void _resetBands() {
    for (var i = 0; i < bandCount; i++) {
      _bandEnergy[i] = 0.0;
    }
  }

  static double? _parseDb(String? value) {
    if (value == null || value == '-inf') return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  /// Convert dB to 0–1 perceptual scale. -60dB = 0, 0dB = 1.
  /// Uses a power curve to spread the musically-useful range (-30..0 dB)
  /// more evenly across the visual output.
  static double _dbToLinear(double db) {
    if (db <= _dbFloor) return 0.0;
    if (db >= 0.0) return 1.0;
    final linear = (db - _dbFloor) / -_dbFloor;
    return math.pow(linear, 0.75).toDouble();
  }

  void dispose() {
    _active = false;
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _spectrumController.close();
  }
}
