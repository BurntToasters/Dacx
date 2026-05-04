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

  String exportText({bool redactSensitive = true}) {
    if (_entries.isEmpty) return 'No debug log entries.';
    final lines = <String>[];
    for (final entry in _entries) {
      lines.add(_formatEntry(entry, redactSensitive: redactSensitive));
    }
    return lines.join('\n');
  }

  String _formatEntry(DebugLogEntry entry, {required bool redactSensitive}) {
    final ts = entry.timestamp.toIso8601String();
    final sev = entry.severity.name.toUpperCase();
    final cat = entry.category.name.toUpperCase();
    final buf = StringBuffer('[$ts] [$sev] [$cat] ${entry.event}');
    final renderedMessage = redactSensitive
        ? _sanitizeText(entry.message)
        : entry.message?.trim();
    if (renderedMessage != null && renderedMessage.isNotEmpty) {
      buf.write(' - $renderedMessage');
    }
    if (entry.details.isNotEmpty) {
      final keys = entry.details.keys.toList()..sort();
      final rendered = keys
          .map((key) {
            final value = entry.details[key];
            final safe = redactSensitive
                ? _sanitizeDetailValue(key, value)
                : value?.toString().replaceAll('\n', r'\n');
            return '$key=$safe';
          })
          .join(', ');
      buf.write(' | $rendered');
    }
    return buf.toString();
  }

  String? _sanitizeDetailValue(String key, Object? value) {
    final text = value?.toString();
    if (text == null) return null;
    if (_isSensitiveKey(key)) return '<redacted>';
    final normalized = text.replaceAll('\n', r'\n');
    if (_isPathLikeKey(key)) {
      return _redactPath(normalized);
    }
    return _sanitizeText(normalized);
  }

  String? _sanitizeText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_looksLikePath(trimmed)) {
      return _redactPath(trimmed);
    }
    return value
        .replaceAllMapped(_pathPattern, (match) {
          final prefix = match.group(1) ?? '';
          final candidate = match.group(2) ?? '';
          return '$prefix${_redactPath(candidate)}';
        })
        .replaceAll('\n', r'\n');
  }

  bool _isPathLikeKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized == 'url' ||
        normalized.endsWith('_url') ||
        normalized.endsWith('uri')) {
      return false;
    }
    return normalized.contains('path') ||
        normalized.contains('file') ||
        normalized.contains('dir') ||
        normalized.contains('cwd');
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('apikey') ||
        normalized.contains('api_key') ||
        normalized.contains('auth') ||
        normalized.contains('email') ||
        normalized.contains('user') ||
        normalized.contains('cookie') ||
        normalized.contains('session');
  }

  bool _looksLikePath(String value) {
    return value.startsWith('/') ||
        value.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  String _redactPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty);
    final basename = segments.isEmpty ? 'path' : segments.last;
    return '<path:$basename>';
  }

  static final RegExp _pathPattern = RegExp(
    r"""(^|[\s(="'])((?:[A-Za-z]:[\\/]|\\\\)[^\s,|;"')]+|/(?!/)[^\s,|;"')]+(?:/[^\s,|;"')]+)*)""",
    multiLine: true,
  );
}
