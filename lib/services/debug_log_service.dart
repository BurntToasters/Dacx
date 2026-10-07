import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/playable_source.dart';
import 'error_log_store.dart';

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

  final ErrorLogStore? _errorStore;

  DebugLogService({
    this._maxEntries = 2000,
    required this._isEnabled,
    this._errorStore,
  });

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
    if (!isEnabled &&
        severity != DebugSeverity.error &&
        category != DebugLogCategory.error) {
      return;
    }
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
    if (!isEnabled &&
        severity != DebugSeverity.error &&
        category != DebugLogCategory.error) {
      return;
    }
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
    final entry = DebugLogEntry(
      timestamp: DateTime.now(),
      category: category,
      severity: severity,
      event: event,
      message: message,
      details: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(details),
      ),
    );
    _entries.add(entry);
    if (severity == DebugSeverity.error || category == DebugLogCategory.error) {
      _errorStore?.append(formatEntry(entry));
    }
    notifyListeners();
  }

  void clear() {
    final store = _errorStore;
    final hadStored = store != null && store.previousSessions.isNotEmpty;
    store?.clear();
    if (_entries.isEmpty && !hadStored) return;
    _entries.clear();
    notifyListeners();
  }

  String exportText({bool redactSensitive = true}) {
    final previous = _errorStore?.previousSessions ?? '';
    final lines = <String>[];
    for (final entry in _entries) {
      lines.add(formatEntry(entry, redactSensitive: redactSensitive));
    }
    if (lines.isEmpty && previous.isEmpty) return 'No debug log entries.';
    if (previous.isEmpty) return lines.join('\n');
    // Stored lines were redacted when written.
    return [
      '--- Errors from earlier sessions ---',
      previous,
      '--- This session ---',
      if (lines.isEmpty) 'No debug log entries.' else ...lines,
    ].join('\n');
  }

  static String formatEntry(
    DebugLogEntry entry, {
    bool redactSensitive = true,
  }) {
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

  static String? _sanitizeDetailValue(String key, Object? value) {
    final text = value?.toString();
    if (text == null) return null;
    if (_isSensitiveKey(key)) return '<redacted>';
    final normalized = text.replaceAll('\n', r'\n');
    if (PlayableSource.isSupportedUrl(normalized)) {
      return PlayableSource.displaySafeUrl(normalized);
    }
    if (_isPathLikeKey(key)) {
      return _redactPath(normalized);
    }
    return _sanitizeText(normalized);
  }

  static String? _sanitizeText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    if (PlayableSource.isSupportedUrl(trimmed)) {
      return PlayableSource.displaySafeUrl(trimmed);
    }
    if (_looksLikePath(trimmed)) {
      return _redactPath(trimmed);
    }
    return value
        // `file://` URIs (debug stack frames) redact as plain paths.
        .replaceAll(_fileUriPrefix, '')
        .replaceAllMapped(_urlPattern, (match) {
          final candidate = match.group(0) ?? '';
          return PlayableSource.displaySafeUrl(candidate);
        })
        // Quoted paths first: the quotes mark the full extent, spaces included.
        .replaceAllMapped(_quotedPathPattern, (match) {
          final quote = match.group(1) ?? '';
          final candidate = match.group(2) ?? '';
          return '$quote${_redactPath(candidate)}$quote';
        })
        .replaceAllMapped(_pathPattern, (match) {
          final prefix = match.group(1) ?? '';
          final candidate = match.group(2) ?? '';
          return '$prefix${_redactPath(candidate)}';
        })
        .replaceAll('\n', r'\n');
  }

  static bool _isPathLikeKey(String key) {
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

  static bool _isSensitiveKey(String key) {
    final words = key
        .split(RegExp(r'(?=[A-Z])|_|-|\s+'))
        .map((w) => w.toLowerCase())
        .toSet();
    const sensitiveWords = {
      'token',
      'secret',
      'password',
      'passwd',
      'apikey',
      'api_key',
      'auth',
      'email',
      'user',
      'cookie',
      'session',
      'username',
      'credential',
      'credentials',
      'key',
      'pass',
      'pw',
    };
    return words.any((w) => sensitiveWords.contains(w));
  }

  static bool _looksLikePath(String value) {
    return value.startsWith('/') ||
        value.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  static String _redactPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty);
    final basename = segments.isEmpty ? 'path' : segments.last;
    return '<path:$basename>';
  }

  static final RegExp _fileUriPrefix = RegExp(
    r'file://(?=/|[A-Za-z]:)',
    caseSensitive: false,
  );

  static final RegExp _quotedPathPattern = RegExp(
    r"""(['"])((?:[A-Za-z]:[\\/]|\\\\|/(?!/))[^'"\n]*)\1""",
  );

  /// Unquoted paths. A path may contain single spaces (`John Smith`), so a
  /// match continues across a space unless the next word starts with `(` (an
  /// OS error suffix). Over-redacting trailing words is safer than leaking a
  /// user or folder name.
  static final RegExp _pathPattern = RegExp(
    r"""(^|[\s(="'])((?:[A-Za-z]:[\\/]|\\\\|/(?!/))[^\s,|;"'<>()]+(?: (?![(])[^\s,|;"'<>()]+)*)""",
    multiLine: true,
  );

  static final RegExp _urlPattern = RegExp(
    r"""https?://[^\s,|;"')<>\]]+""",
    caseSensitive: false,
  );
}
