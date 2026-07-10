import 'package:dacx/services/debug_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DebugLogService', () {
    late DebugLogService service;

    setUp(() {
      service = DebugLogService(isEnabled: () => true);
    });

    test('initially empty', () {
      expect(service.entryCount, 0);
      expect(service.entries, isEmpty);
      expect(service.isEnabled, isTrue);
    });

    test('log adds entry', () {
      service.log(
        category: DebugLogCategory.playback,
        event: 'test_event',
        message: 'hello',
      );
      expect(service.entryCount, 1);
      expect(service.entries.first.event, 'test_event');
      expect(service.entries.first.message, 'hello');
      expect(service.entries.first.category, DebugLogCategory.playback);
      expect(service.entries.first.severity, DebugSeverity.info);
    });

    test('log with details', () {
      service.log(
        category: DebugLogCategory.update,
        event: 'check',
        details: {'version': '1.0.0', 'channel': 'stable'},
      );
      expect(service.entries.first.details['version'], '1.0.0');
      expect(service.entries.first.details['channel'], 'stable');
    });

    test('logLazy calls builders lazily', () {
      var messageCalled = false;
      var detailsCalled = false;
      service.logLazy(
        category: DebugLogCategory.system,
        event: 'lazy_test',
        messageBuilder: () {
          messageCalled = true;
          return 'lazy msg';
        },
        detailsBuilder: () {
          detailsCalled = true;
          return {'key': 'val'};
        },
      );
      expect(messageCalled, isTrue);
      expect(detailsCalled, isTrue);
      expect(service.entries.first.message, 'lazy msg');
      expect(service.entries.first.details['key'], 'val');
    });

    test('logLazy does not call builders when disabled (non-error)', () {
      final disabled = DebugLogService(isEnabled: () => false);
      var called = false;
      disabled.logLazy(
        category: DebugLogCategory.playback,
        event: 'skipped',
        messageBuilder: () {
          called = true;
          return 'msg';
        },
      );
      expect(called, isFalse);
      expect(disabled.entryCount, 0);
    });

    test('error severity is always logged even when disabled', () {
      final disabled = DebugLogService(isEnabled: () => false);
      disabled.log(
        category: DebugLogCategory.playback,
        event: 'crash',
        severity: DebugSeverity.error,
      );
      expect(disabled.entryCount, 1);
    });

    test('error category is always logged even when disabled', () {
      final disabled = DebugLogService(isEnabled: () => false);
      disabled.log(category: DebugLogCategory.error, event: 'fatal');
      expect(disabled.entryCount, 1);
    });

    test('clear removes all entries', () {
      service.log(category: DebugLogCategory.ui, event: 'a');
      service.log(category: DebugLogCategory.ui, event: 'b');
      expect(service.entryCount, 2);
      service.clear();
      expect(service.entryCount, 0);
    });

    test('clear on empty does not notify', () {
      var notified = false;
      service.addListener(() => notified = true);
      service.clear();
      expect(notified, isFalse);
    });

    test('max entries eviction', () {
      final small = DebugLogService(maxEntries: 3, isEnabled: () => true);
      small.log(category: DebugLogCategory.ui, event: 'a');
      small.log(category: DebugLogCategory.ui, event: 'b');
      small.log(category: DebugLogCategory.ui, event: 'c');
      small.log(category: DebugLogCategory.ui, event: 'd');
      expect(small.entryCount, 3);
      expect(small.entries.first.event, 'b');
      expect(small.entries.last.event, 'd');
    });

    test('exportText when empty', () {
      expect(service.exportText(), 'No debug log entries.');
    });

    test('exportText includes event and severity', () {
      service.log(
        category: DebugLogCategory.update,
        event: 'check_started',
        message: 'checking',
        severity: DebugSeverity.warn,
      );
      final text = service.exportText();
      expect(text, contains('check_started'));
      expect(text, contains('WARN'));
      expect(text, contains('UPDATE'));
    });

    test('notifyListeners fires on log', () {
      var notified = false;
      service.addListener(() => notified = true);
      service.log(category: DebugLogCategory.ui, event: 'x');
      expect(notified, isTrue);
    });
  });

  group('DebugLogService.formatEntry', () {
    test('formats basic entry', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.playback,
        severity: DebugSeverity.info,
        event: 'play_started',
        message: 'playing file',
      );
      final text = DebugLogService.formatEntry(entry);
      expect(text, contains('[INFO]'));
      expect(text, contains('[PLAYBACK]'));
      expect(text, contains('play_started'));
    });

    test('redacts path-like values by default', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.playback,
        severity: DebugSeverity.info,
        event: 'open',
        details: const {'file_path': '/home/user/secret/music.mp3'},
      );
      final text = DebugLogService.formatEntry(entry);
      expect(text, contains('<path:music.mp3>'));
      expect(text, isNot(contains('/home/user/secret')));
    });

    test('redacts sensitive keys', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.system,
        severity: DebugSeverity.info,
        event: 'auth',
        details: const {'auth_token': 'abc123secret'},
      );
      final text = DebugLogService.formatEntry(entry);
      expect(text, contains('<redacted>'));
      expect(text, isNot(contains('abc123secret')));
    });

    test('does not redact when redactSensitive is false', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.system,
        severity: DebugSeverity.info,
        event: 'test',
        details: const {'file_path': '/home/user/music.mp3'},
      );
      final text = DebugLogService.formatEntry(entry, redactSensitive: false);
      expect(text, contains('/home/user/music.mp3'));
    });

    test('handles null message gracefully', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.ui,
        severity: DebugSeverity.info,
        event: 'no_msg',
      );
      final text = DebugLogService.formatEntry(entry);
      expect(text, contains('no_msg'));
      expect(text, isNot(contains(' - ')));
    });

    test('handles empty details', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.ui,
        severity: DebugSeverity.info,
        event: 'empty_details',
      );
      final text = DebugLogService.formatEntry(entry);
      expect(text, isNot(contains('|')));
    });

    test('sanitizes URLs in messages', () {
      final entry = DebugLogEntry(
        timestamp: DateTime(2026, 7, 8, 12, 0, 0),
        category: DebugLogCategory.playback,
        severity: DebugSeverity.info,
        event: 'stream',
        message:
            'playing https://stream.example.com/secret/path/file.mp3?token=abc',
      );
      final text = DebugLogService.formatEntry(entry);
      // URL query params should be redacted
      expect(text, isNot(contains('token=abc')));
    });
  });
}
