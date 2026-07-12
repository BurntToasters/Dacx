import 'dart:async';

import 'package:flutter/foundation.dart';

/// Stops playback after a chosen delay.
///
/// Extracted from [PlayerScreen] so timer math and fire behavior stay
/// unit-testable without the full widget tree.
class SleepTimerController extends ChangeNotifier {
  SleepTimerController({
    VoidCallback? onFire,
    DateTime Function()? clock,
  }) : _onFire = onFire,
       _clock = clock ?? DateTime.now;

  /// Supported preset lengths in minutes (excluding off/cancel).
  static const List<int> presetMinutes = [15, 30, 45, 60];

  VoidCallback? _onFire;
  final DateTime Function() _clock;

  Timer? _fireTimer;
  Timer? _tickTimer;
  DateTime? _endsAt;
  bool _disposed = false;

  /// Invoked once when the timer reaches zero (parent should stop playback).
  set onFire(VoidCallback? callback) => _onFire = callback;

  /// Whether a timer is currently scheduled.
  bool get isActive => _endsAt != null;

  /// Time left until fire, or `null` when inactive.
  Duration? get remaining =>
      computeRemaining(endsAt: _endsAt, now: _clock());

  /// Pure remaining-time math (unit-testable without [Timer]).
  static Duration? computeRemaining({
    required DateTime? endsAt,
    required DateTime now,
  }) {
    if (endsAt == null) return null;
    final left = endsAt.difference(now);
    if (left.isNegative) return Duration.zero;
    return left;
  }

  /// Start (or restart) a sleep timer for [duration].
  void start(Duration duration) {
    if (_disposed) return;
    cancel(notify: false);
    if (duration <= Duration.zero) {
      notifyListeners();
      return;
    }
    _endsAt = _clock().add(duration);
    _fireTimer = Timer(duration, _handleFire);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _endsAt == null) return;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Convenience for [presetMinutes] values.
  void startMinutes(int minutes) => start(Duration(minutes: minutes));

  /// Cancel the active timer without firing.
  void cancel({bool notify = true}) {
    _fireTimer?.cancel();
    _fireTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _endsAt = null;
    if (notify && !_disposed) notifyListeners();
  }

  void _handleFire() {
    _fireTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _endsAt = null;
    if (_disposed) return;
    notifyListeners();
    _onFire?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel(notify: false);
    super.dispose();
  }
}
