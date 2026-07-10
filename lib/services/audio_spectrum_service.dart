import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'player_service.dart';

/// Polls true frequency-band energy metadata from mpv's `astats` audio filter.
///
/// The filter graph builds a parallel probe branch:
/// 1) duplicate the input,
/// 2) split a mono probe signal into logarithmic crossover bands,
/// 3) merge the main stereo path with probe bands,
/// 4) measure per-channel RMS with astats metadata,
/// 5) map output back to the original stereo channels.
class AudioSpectrumService {
  AudioSpectrumService({
    required PlayerService playerService,
    this.bandCount = 32,
    this.pollInterval = const Duration(milliseconds: 33),
  }) : _playerService = playerService;

  final PlayerService _playerService;
  final int bandCount;
  final Duration pollInterval;

  Timer? _pollTimer;
  bool _active = false;
  int _pollSession = 0;
  bool _pollInFlight = false;

  // Current state
  late final List<double> _lastBandDb = List<double>.filled(
    _graphBandCount,
    _dbFloor,
  );

  late final List<double> _bandEnergy = List<double>.filled(bandCount, 0.0);
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  /// Stream of per-band energy values (0.0–1.0), emitted at poll rate.
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  /// Current band energies (for synchronous read).
  List<double> get currentSpectrum => _bandEnergy;

  bool get isActive => _active;

  /// The af filter segment this service needs appended to the chain.
  static const String _afLabel = 'dacxstats';
  static const int _graphBandCount = 32;
  static const double _dbFloor = -80.0;
  static const int _firstBandChannel = 3;
  static final String afSegment = _buildAfSegment();
  static const String _fallbackRmsProperty =
      'af-metadata/$_afLabel/by-key/lavfi.astats.Overall.RMS_level';
  static const String _fallbackPeakProperty =
      'af-metadata/$_afLabel/by-key/lavfi.astats.Overall.Peak_level';

  /// Start polling. Call after playback begins.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _pollSession++;
    resetDynamics();
    await _installFilter();
    if (!_active) return;
    _pollTimer?.cancel();
    final session = _pollSession;
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick(session));
  }

  /// Stop polling and remove filter.
  Future<void> stop() async {
    _pollSession++;
    _active = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    resetDynamics();
    // Stop emitting non-zero bars immediately when playback pauses/stops.
    for (var i = 0; i < bandCount; i++) {
      _bandEnergy[i] = 0.0;
    }
    if (!_spectrumController.isClosed) {
      _spectrumController.add(List<double>.from(_bandEnergy));
    }
  }

  /// Must be called when af chain is rebuilt (e.g. EQ toggled).
  /// Signals that the merged af chain needs to be re-applied.
  void markFilterDirty() {
    // No-op: caller manages af chain rebuild.
  }

  Future<void> _installFilter() async {
    // The caller (player_screen) manages the merged af chain.
    // This method exists as a hook for future per-service filter setup.
  }

  Future<void> _pollOnce() async {
    if (!_active || _playerService.isDisposed) return;

    if (_pollInFlight) return;
    _pollInFlight = true;

    try {
      var measuredBand = false;
      final targetBands = math.min(bandCount, _graphBandCount);
      for (var i = 0; i < targetBands; i++) {
        final key = _bandProperty(i);
        final value = await _playerService.getProperty(key);
        final parsed = _parseDb(value);
        if (parsed != null) {
          _lastBandDb[i] = parsed;
          measuredBand = true;
        }
      }

      if (measuredBand) {
        _updateSpectrumFromBands();
      } else {
        await _updateSpectrumFallback();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioSpectrumService poll error: $e');
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _pollTick(int session) async {
    if (!_active || _playerService.isDisposed || session != _pollSession) {
      return;
    }
    await _pollOnce();
  }

  void resetDynamics() {
    for (var i = 0; i < _lastBandDb.length; i++) {
      _lastBandDb[i] = _dbFloor;
    }
  }

  void _updateSpectrumFromBands() {
    final targetBands = math.min(bandCount, _graphBandCount);
    for (var i = 0; i < targetBands; i++) {
      final t = targetBands <= 1 ? 0.0 : i / (targetBands - 1);
      final target = _dbToLinear(_lastBandDb[i]);

      final attackRate = 0.58 + 0.30 * t;
      final releaseRate = 0.78 + 0.17 * (1.0 - t);

      if (target > _bandEnergy[i]) {
        _bandEnergy[i] =
            _bandEnergy[i] * (1.0 - attackRate) + target * attackRate;
      } else {
        _bandEnergy[i] =
            _bandEnergy[i] * releaseRate + target * (1.0 - releaseRate);
      }
      _bandEnergy[i] = _bandEnergy[i].clamp(0.0, 1.0);
    }

    for (var i = targetBands; i < bandCount; i++) {
      _bandEnergy[i] = _bandEnergy[i] * 0.85;
    }

    if (!_spectrumController.isClosed) {
      _spectrumController.add(List<double>.from(_bandEnergy));
    }
  }

  Future<void> _updateSpectrumFallback() async {
    final rms = _parseDb(
      await _playerService.getProperty(_fallbackRmsProperty),
    );
    final peak = _parseDb(
      await _playerService.getProperty(_fallbackPeakProperty),
    );
    final base = _dbToLinear(math.max(rms ?? _dbFloor, peak ?? _dbFloor));
    for (var i = 0; i < bandCount; i++) {
      _bandEnergy[i] = (_bandEnergy[i] * 0.86 + base * 0.14).clamp(0.0, 1.0);
    }

    if (!_spectrumController.isClosed) {
      _spectrumController.add(List<double>.from(_bandEnergy));
    }
  }

  static double? _parseDb(String? value) {
    if (value == null || value == '-inf') return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  static String _bandProperty(int bandIndex) {
    final channel = _firstBandChannel + bandIndex;
    return 'af-metadata/$_afLabel/by-key/lavfi.astats.$channel.RMS_level';
  }

  static String _buildAfSegment() {
    final splitPoints = _buildCrossoverSplits(
      _graphBandCount,
      20.0,
      20000.0,
    ).map((v) => v.toStringAsFixed(2)).join(' ');
    final bandLabels = List<String>.generate(
      _graphBandCount,
      (i) => '[b$i]',
      growable: false,
    );
    final mergedInputs = <String>['[main]', ...bandLabels].join();

    final graph =
        '[in]aformat=channel_layouts=stereo,asplit=2[main][probe];'
        '[probe]pan=mono|c0=0.5*c0+0.5*c1,acrossover=split=$splitPoints:order=8th${bandLabels.join()} ;'
        '$mergedInputs'
        'amerge=inputs=${_graphBandCount + 1}[merged];'
        '[merged]astats=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=RMS_level+Peak_level,pan=stereo|c0=c0|c1=c1[out]';
    return '@$_afLabel:lavfi=[$graph]';
  }

  static List<double> _buildCrossoverSplits(
    int bands,
    double minHz,
    double maxHz,
  ) {
    if (bands < 2) return const [];
    final boundaries = List<double>.generate(bands + 1, (i) {
      final t = i / bands;
      return minHz * math.pow(maxHz / minHz, t).toDouble();
    });
    return boundaries.sublist(1, boundaries.length - 1);
  }

  /// Convert dB to 0–1 perceptual scale. -60dB = 0, 0dB = 1.
  /// Uses a power curve to spread the musically-useful range (-30..0 dB)
  /// more evenly across the visual output.
  static double _dbToLinear(double db) {
    if (db <= _dbFloor) return 0.0;
    if (db >= 0.0) return 1.0;
    final linear = (db - _dbFloor) / -_dbFloor;
    return math.pow(linear, 0.82).toDouble();
  }

  void dispose() {
    _active = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _spectrumController.close();
  }
}
