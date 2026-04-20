import 'dart:collection';

import 'package:flutter/foundation.dart';

enum DebugLogCategory { playback, settings, update, hwaccel, ui, system, error }

enum DebugSeverity { info, warn, error }

@immutable
class DebugLogEntry {
  final DateTime timestamp;
  final DebugLogCategory category;
  final DebugSeverity severity;
  final String event;
  final String? message;
  final Map<String, Object?> details;

  const DebugLogEntry({
    required this.timestamp,
    required this.category,
    required this.severity,
    required this.event,
    this.message,
    this.details = const {},
  });
}

class DebugLogService extends ChangeNotifier {
  final int _maxEntries;
  final bool Function() _isEnabled;
  final ListQueue<DebugLogEntry> _entries = ListQueue<DebugLogEntry>();

  DebugLogService({int maxEntries = 2000, required bool Function() isEnabled})
    : _maxEntries = maxEntries,
      _isEnabled = isEnabled;

  List<DebugLogEntry> get entries => List<DebugLogEntry>.unmodifiable(_entries);

  int get entryCount => _entries.length;
  bool get isEnabled => _isEnabled();

  void log({
    required DebugLogCategory category,
    required String event,
    String? message,
    Map<String, Object?> details = const {},
    DebugSeverity severity = DebugSeverity.info,
  }) {
    if (!isEnabled) return;
    _appendEntry(
      category: category,
      event: event,
      message: message,
      details: details,
      severity: severity,
    );
  }

  void logLazy({
    required DebugLogCategory category,
    required String event,
    String? Function()? messageBuilder,
    Map<String, Object?> Function()? detailsBuilder,
    DebugSeverity severity = DebugSeverity.info,
  }) {
    if (!isEnabled) return;
    _appendEntry(
      category: category,
      event: event,
      message: messageBuilder?.call(),
      details: detailsBuilder?.call() ?? const {},
      severity: severity,
    );
  }

  void _appendEntry({
    required DebugLogCategory category,
    required String event,
    String? message,
    Map<String, Object?> details = const {},
    DebugSeverity severity = DebugSeverity.info,
  }) {
    if (_entries.length == _maxEntries) {
      _entries.removeFirst();
    }
    _entries.add(
      DebugLogEntry(
        timestamp: DateTime.now(),
        category: category,
        severity: severity,
        event: event,
        message: message,
        details: Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(details),
        ),
      ),
    );
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  String exportText() {
    if (_entries.isEmpty) return 'No debug log entries.';
    final lines = <String>[];
    for (final entry in _entries) {
      lines.add(_formatEntry(entry));
    }
    return lines.join('\n');
  }

  String _formatEntry(DebugLogEntry entry) {
    final ts = entry.timestamp.toIso8601String();
    final sev = entry.severity.name.toUpperCase();
    final cat = entry.category.name.toUpperCase();
    final buf = StringBuffer('[$ts] [$sev] [$cat] ${entry.event}');
    if (entry.message != null && entry.message!.trim().isNotEmpty) {
      buf.write(' - ${entry.message!.trim()}');
    }
    if (entry.details.isNotEmpty) {
      final keys = entry.details.keys.toList()..sort();
      final rendered = keys
          .map((key) {
            final value = entry.details[key];
            final safe = value?.toString().replaceAll('\n', r'\n');
            return '$key=$safe';
          })
          .join(', ');
      buf.write(' | $rendered');
    }
    return buf.toString();
  }
}
