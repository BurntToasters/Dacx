import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'player_service.dart';

/// Polls per-band RMS energy from labeled mpv `lavfi`/`astats` analysis filters
/// and emits [bandCount] energies (0–1) for visualization.
///
/// Each analysis filter splits audio, measures a frequency band, sinks the
/// analysis path, and passes the original audio through unchanged. Labels are
/// unique so `af-metadata/<label>/...` keys do not collide.
///
/// Polling never starts until [confirmFilterInstalled] — reading `af-metadata`
/// without a live labeled filter can crash native mpv.
class AudioSpectrumService {
  AudioSpectrumService({
    required IPlayerService playerService,
    this.bandCount = 32,
    this.pollInterval = const Duration(milliseconds: 40),
    this.probeFailLimit = 12,
  }) : _playerService = playerService,
       bandsNotifier = ValueNotifier<List<double>>(
         List<double>.filled(bandCount, 0.0),
       );

  final IPlayerService _playerService;
  final int bandCount;
  final Duration pollInterval;
  final int probeFailLimit;

  Timer? _pollTimer;
  bool _active = false;
  bool _filterInstalled = false;
  int _pollSession = 0;
  bool _pollInFlight = false;
  int _emptyPolls = 0;
  bool _capabilityFailed = false;

  late final List<double> _bandEnergy = List<double>.filled(bandCount, 0.0);
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  final ValueNotifier<List<double>> bandsNotifier;

  /// Stream of per-band energy values (0.0–1.0), emitted at poll rate.
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  List<double> get currentSpectrum => _bandEnergy;

  bool get isActive => _active;

  bool get isFilterInstalled => _filterInstalled;

  /// True after repeated empty metadata polls — caller should disable + toast.
  bool get capabilityFailed => _capabilityFailed;

  /// Number of frequency analysis bands installed in the af chain.
  static const int analysisBandCount = 4;

  static const double _dbFloor = -60.0;

  /// Labeled pass-through analysis filters (bass → treble).
  static const List<String> afSegments = [
    '@dacxb0:lavfi=[asplit[m][s];[s]lowpass=f=200,astats=metadata=1:reset=1:measure_overall=RMS_level,anullsink;[m]anull]',
    '@dacxb1:lavfi=[asplit[m][s];[s]bandpass=f=700:width_type=h:width=900,astats=metadata=1:reset=1:measure_overall=RMS_level,anullsink;[m]anull]',
    '@dacxb2:lavfi=[asplit[m][s];[s]bandpass=f=3000:width_type=h:width=3500,astats=metadata=1:reset=1:measure_overall=RMS_level,anullsink;[m]anull]',
    '@dacxb3:lavfi=[asplit[m][s];[s]highpass=f=8000,astats=metadata=1:reset=1:measure_overall=RMS_level,anullsink;[m]anull]',
  ];

  /// Joined af chain segment(s) for spectrum analysis (backward-compatible name).
  static String get afSegment => afSegments.join(',');

  static const List<String> _rmsProperties = [
    'af-metadata/dacxb0/lavfi.astats.Overall.RMS_level',
    'af-metadata/dacxb1/lavfi.astats.Overall.RMS_level',
    'af-metadata/dacxb2/lavfi.astats.Overall.RMS_level',
    'af-metadata/dacxb3/lavfi.astats.Overall.RMS_level',
  ];

  Future<void> start() async {
    if (_active) return;
    _active = true;
    _filterInstalled = false;
    _capabilityFailed = false;
    _emptyPolls = 0;
    _pollSession++;
    _resetBands();
    _emitBands();
  }

  void confirmFilterInstalled() {
    if (!_active) return;
    _filterInstalled = true;
    _capabilityFailed = false;
    _emptyPolls = 0;
    _pollTimer?.cancel();
    final session = _pollSession;
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick(session));
  }

  void confirmFilterFailed() {
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> stop() async {
    _pollSession++;
    _active = false;
    _filterInstalled = false;
    _capabilityFailed = false;
    _emptyPolls = 0;
    _pollTimer?.cancel();
    _pollTimer = null;
    _resetBands();
    _emitBands();
  }

  /// Pause polling until [confirmFilterInstalled] after an af rebuild.
  void markFilterDirty() {
    _filterInstalled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

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

    final bandDbs = <double?>[];
    var any = false;
    for (final prop in _rmsProperties) {
      final db = _parseDb(await _playerService.getProperty(prop));
      bandDbs.add(db);
      if (db != null) any = true;
    }

    if (!any) {
      _emptyPolls++;
      if (_emptyPolls >= probeFailLimit) {
        _capabilityFailed = true;
        confirmFilterFailed();
        _resetBands();
        _emitBands();
      }
      return;
    }
    _emptyPolls = 0;

    final energies = bandDbs
        .map((db) => _dbToLinear(db ?? _dbFloor))
        .toList(growable: false);
    _distributeBandEnergies(energies);
  }

  /// Interpolates [analysisBandCount] measured energies across [bandCount]
  /// display bars with a single attack/release stage.
  void _distributeBandEnergies(List<double> measured) {
    final n = measured.length;
    if (n == 0) return;

    for (var i = 0; i < bandCount; i++) {
      final position = bandCount <= 1 ? 0.0 : i / (bandCount - 1);
      final scaled = position * (n - 1);
      final lo = scaled.floor().clamp(0, n - 1);
      final hi = scaled.ceil().clamp(0, n - 1);
      final t = scaled - lo;
      final target = (measured[lo] * (1.0 - t) + measured[hi] * t).clamp(
        0.0,
        1.0,
      );

      final attackRate = 0.55 + 0.30 * position;
      final releaseRate = 0.78 + 0.14 * (1.0 - position);

      if (target > _bandEnergy[i]) {
        _bandEnergy[i] =
            _bandEnergy[i] * (1.0 - attackRate) + target * attackRate;
      } else {
        _bandEnergy[i] =
            _bandEnergy[i] * releaseRate + target * (1.0 - releaseRate);
      }
      _bandEnergy[i] = _bandEnergy[i].clamp(0.0, 1.0);
    }

    _emitBands();
  }

  void resetDynamics() {
    _resetBands();
    _emitBands();
  }

  void _resetBands() {
    for (var i = 0; i < bandCount; i++) {
      _bandEnergy[i] = 0.0;
    }
  }

  void _emitBands() {
    final snapshot = List<double>.from(_bandEnergy);
    if (!_spectrumController.isClosed) {
      _spectrumController.add(snapshot);
    }
    bandsNotifier.value = snapshot;
  }

  static double? _parseDb(String? value) {
    if (value == null || value == '-inf') return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

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
    if (!_spectrumController.isClosed) {
      _spectrumController.close();
    }
    // Don't dispose bandsNotifier here — callers (PlayerScreen) may still
    // hold a reference during widget teardown. Zero it instead.
    bandsNotifier.value = List<double>.filled(bandCount, 0.0);
  }
}
