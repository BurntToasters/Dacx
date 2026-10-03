import 'package:flutter/foundation.dart';

import '../models/playable_source.dart';
import '../playback/advanced_playback_models.dart';
import 'player_service.dart';
import 'settings_service.dart';

enum AdvancedLoopStage { clear, aSet, active }

/// Owns the opt-in playback tools and their mpv/persistence boundary.
///
/// [PlayerScreen] supplies lifecycle events and renders the state; it does not
/// own preference parsing or mpv property policy.
class AdvancedPlaybackController extends ChangeNotifier {
  AdvancedPlaybackController({
    required SettingsService settings,
    required this._player,
  }) : _settings = settings,
       _lastEnabled = settings.advancedPlaybackToolsEnabled;

  final SettingsService _settings;
  final IPlayerService _player;

  String? _source;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _a;
  Duration? _b;
  bool _applying = false;
  bool _lastEnabled;
  bool _runtimeApplied = false;

  String? _errorMessage;

  String? get source => _source;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration? get a => _a;
  Duration? get b => _b;
  AdvancedLoopStage get loopStage {
    if (_a == null) return AdvancedLoopStage.clear;
    if (_b == null) return AdvancedLoopStage.aSet;
    return AdvancedLoopStage.active;
  }

  String? get errorMessage => _errorMessage;

  void _setError(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    notifyListeners();
  }

  bool get enabled => _settings.advancedPlaybackToolsEnabled;

  PlaybackAdjustment get adjustment => _source == null
      ? const PlaybackAdjustment()
      : _settings.playbackAdjustmentFor(_source!);

  List<PlaybackMarker> get markers => _source == null
      ? const []
      : _settings
            .playbackMarkersFor(_source!)
            .where(
              (marker) =>
                  _duration.inMilliseconds <= 0 ||
                  marker.positionMs <= _duration.inMilliseconds,
            )
            .toList(growable: false);

  Future<void> setSource(PlayableSource? source) async {
    final next = source?.value.trim();
    if (next == _source) {
      if (next == null) await clearLoop();
      return;
    }
    await clearLoop();
    _a = null;
    _b = null;
    _source = next == null || next.isEmpty ? null : next;
    _position = Duration.zero;
    await applyForCurrentSource();
    notifyListeners();
  }

  void setPosition(Duration value) {
    final next = value < Duration.zero ? Duration.zero : value;
    if (next == _position) return;
    _position = next;
    notifyListeners();
  }

  void setDuration(Duration value) {
    final next = value < Duration.zero ? Duration.zero : value;
    if (next == _duration) return;
    _duration = next;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_lastEnabled == value) return;
    _lastEnabled = value;
    _settings.advancedPlaybackToolsEnabled = value;
    if (!value) {
      await clearLoop();
      if (_runtimeApplied) {
        await _restoreMpvDefaults();
        _runtimeApplied = false;
      }
      _a = null;
      _b = null;
    } else {
      await applyForCurrentSource();
    }
    notifyListeners();
  }

  Future<void> applyForCurrentSource() async {
    if (_applying) return;
    _applying = true;
    try {
      if (!enabled || _source == null) return;
      _runtimeApplied = true;
      final value = adjustment;
      final audioApplied = await _player.setProperty(
        'audio-delay',
        _delayValue(value.audioMs),
      );
      final subtitleApplied = await _player.setProperty(
        'sub-delay',
        _delayValue(value.subtitleMs),
      );
      final appearanceApplied = await _applySubtitleAppearance();
      if (!audioApplied || !subtitleApplied) {
        _setError('Could not apply saved playback synchronization.');
      } else if (!appearanceApplied) {
        _setError('Could not apply subtitle appearance.');
      } else {
        _setError(null);
      }
    } finally {
      _applying = false;
    }
  }

  Future<void> adjustAudioDelay(int deltaMs) async {
    if (!enabled || _source == null) return;
    final current = adjustment;
    final next = (current.audioMs + deltaMs).clamp(
      -SettingsService.playbackDelayLimitMs,
      SettingsService.playbackDelayLimitMs,
    );
    final applied = await _player.setProperty('audio-delay', _delayValue(next));
    if (!applied) {
      _setError('Could not apply audio delay.');
      return;
    }
    _settings.setPlaybackAdjustment(
      _source!,
      audioMs: next,
      subtitleMs: current.subtitleMs,
    );
    _setError(null);
    notifyListeners();
  }

  Future<void> adjustSubtitleDelay(int deltaMs) async {
    if (!enabled || _source == null) return;
    final current = adjustment;
    final next = (current.subtitleMs + deltaMs).clamp(
      -SettingsService.playbackDelayLimitMs,
      SettingsService.playbackDelayLimitMs,
    );
    final applied = await _player.setProperty('sub-delay', _delayValue(next));
    if (!applied) {
      _setError('Could not apply subtitle delay.');
      return;
    }
    _settings.setPlaybackAdjustment(
      _source!,
      audioMs: current.audioMs,
      subtitleMs: next,
    );
    _setError(null);
    notifyListeners();
  }

  Future<void> resetAudioDelay() async {
    if (!enabled || _source == null) return;
    final current = adjustment;
    final applied = await _player.setProperty('audio-delay', '0');
    if (!applied) {
      _setError('Could not reset audio delay.');
      return;
    }
    _settings.setPlaybackAdjustment(
      _source!,
      audioMs: 0,
      subtitleMs: current.subtitleMs,
    );
    _setError(null);
    notifyListeners();
  }

  Future<void> resetSubtitleDelay() async {
    if (!enabled || _source == null) return;
    final current = adjustment;
    final applied = await _player.setProperty('sub-delay', '0');
    if (!applied) {
      _setError('Could not reset subtitle delay.');
      return;
    }
    _settings.setPlaybackAdjustment(
      _source!,
      audioMs: current.audioMs,
      subtitleMs: 0,
    );
    _setError(null);
    notifyListeners();
  }

  Future<void> resetDelays() async {
    await resetAudioDelay();
    await resetSubtitleDelay();
  }

  Future<void> cycleLoop() async {
    if (!enabled || _source == null) return;
    if (_a == null) {
      final applied = await _player.setProperty(
        'ab-loop-a',
        _seconds(_position),
      );
      if (!applied) {
        _setError('Could not apply A-B repeat.');
        return;
      }
      _a = _position;
      _b = null;
    } else if (_b == null) {
      // An empty/reversed range cannot be represented safely by mpv.
      if (_position <= _a!) {
        await clearLoop();
        return;
      }
      final applied = await _player.setProperty(
        'ab-loop-b',
        _seconds(_position),
      );
      if (!applied) {
        _setError('Could not apply A-B repeat.');
        return;
      }
      _b = _position;
    } else {
      final aCleared = await _player.setProperty('ab-loop-a', 'no');
      final bCleared = await _player.setProperty('ab-loop-b', 'no');
      if (!aCleared || !bCleared) {
        _setError('Could not clear A-B repeat.');
        return;
      }
      _a = null;
      _b = null;
      _setError(null);
      return;
    }
    notifyListeners();
  }

  Future<void> clearLoop() async {
    final hadLoop = _a != null || _b != null;
    if (!hadLoop) return;
    if (!enabled) {
      _a = null;
      _b = null;
      notifyListeners();
      return;
    }
    final aCleared = await _player.setProperty('ab-loop-a', 'no');
    final bCleared = await _player.setProperty('ab-loop-b', 'no');
    if (!aCleared || !bCleared) {
      _setError('Could not clear A-B repeat.');
      notifyListeners();
      return;
    }
    _setError(null);
    _a = null;
    _b = null;
    if (hadLoop) notifyListeners();
  }

  PlaybackMarker? addMarker({String? label}) {
    if (!enabled || _source == null) return null;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : SettingsService.playbackMarkerPositionLimitMs;
    final positionMs = _position.inMilliseconds.clamp(0, maxMs);
    final marker = PlaybackMarker(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      positionMs: positionMs,
      label: _safeLabel(label) ?? _formatTimestamp(_position),
    );
    _settings.addPlaybackMarker(_source!, marker);
    notifyListeners();
    return marker;
  }

  void renameMarker(String id, String label) {
    if (!enabled || _source == null) return;
    final safe = _safeLabel(label);
    if (safe == null) return;
    _settings.updatePlaybackMarker(_source!, id, label: safe);
    notifyListeners();
  }

  Future<void> seekMarker(PlaybackMarker marker) async {
    if (!enabled || _source == null) return;
    await _player.seek(Duration(milliseconds: marker.positionMs));
    setPosition(Duration(milliseconds: marker.positionMs));
  }

  void deleteMarker(String id) {
    if (!enabled || _source == null) return;
    _settings.removePlaybackMarker(_source!, id);
    notifyListeners();
  }

  Future<void> applySubtitleAppearance() async {
    if (!enabled || _source == null) return;
    _runtimeApplied = true;
    final applied = await _applySubtitleAppearance();
    _setError(applied ? null : 'Could not apply subtitle appearance.');
  }

  Future<bool> _applySubtitleAppearance() async {
    final results = <bool>[
      await _player.setProperty(
        'sub-font-size',
        _settings.subtitleFontSize.toString(),
      ),
      await _player.setProperty(
        'sub-pos',
        _settings.subtitlePosition.toString(),
      ),
      await _player.setProperty(
        'sub-outline-size',
        _settings.subtitleOutlineSize.toString(),
      ),
      await _player.setProperty('sub-color', _settings.subtitleTextColor),
      await _player.setProperty(
        'sub-border-color',
        _settings.subtitleOutlineColor,
      ),
    ];
    // Preserve authored ASS/SSA style declarations.
    results.add(await _player.setProperty('sub-ass-override', 'no'));
    return results.every((applied) => applied);
  }

  Future<void> _restoreMpvDefaults() async {
    await _player.setProperty('ab-loop-a', 'no');
    await _player.setProperty('ab-loop-b', 'no');
    await _player.setProperty('audio-delay', '0');
    await _player.setProperty('sub-delay', '0');
    await _player.setProperty(
      'sub-font-size',
      SettingsService.subtitleFontSizeDefault.toString(),
    );
    await _player.setProperty(
      'sub-pos',
      SettingsService.subtitlePositionDefault.toString(),
    );
    await _player.setProperty(
      'sub-outline-size',
      SettingsService.subtitleOutlineSizeDefault.toString(),
    );
    await _player.setProperty(
      'sub-color',
      SettingsService.subtitleTextColorDefault,
    );
    await _player.setProperty(
      'sub-border-color',
      SettingsService.subtitleOutlineColorDefault,
    );
    await _player.setProperty('sub-ass-override', 'no');
  }

  static String _seconds(Duration value) =>
      (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(
        3,
      );

  static String _delayValue(int milliseconds) =>
      (milliseconds / Duration.millisecondsPerSecond).toStringAsFixed(3);

  static String _formatTimestamp(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String? _safeLabel(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 80) return null;
    if (trimmed.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      return null;
    }
    return trimmed;
  }
}
