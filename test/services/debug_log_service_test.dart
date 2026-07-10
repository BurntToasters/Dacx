import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/debug_log_service.dart';

void main() {
  group('DebugLogService', () {
    test('keeps only newest entries up to the ring-buffer limit', () {
      final service = DebugLogService(maxEntries: 3, isEnabled: () => true);

      for (var i = 0; i < 5; i++) {
        service.log(
          category: DebugLogCategory.playback,
          event: 'event_$i',
          details: {'index': i},
        );
      }

      expect(service.entryCount, 3);
      expect(service.entries.map((e) => e.event).toList(), [
        'event_2',
        'event_3',
        'event_4',
      ]);
    });

    test(
      'exportText includes timestamp, severity, category, event, and details',
      () {
        final service = DebugLogService(isEnabled: () => true);

        service.log(
          category: DebugLogCategory.system,
          severity: DebugSeverity.warn,
          event: 'startup',
          message: 'ready',
          details: {'b': 'two', 'a': 1},
        );

        final output = service.exportText();

        expect(output, contains('[WARN]'));
        expect(output, contains('[SYSTEM]'));
        expect(output, contains('startup'));
        expect(output, contains('ready'));
        expect(output, contains('a=1, b=two'));
        expect(output, matches(RegExp(r'^\[\d{4}-\d{2}-\d{2}T')));
      },
    );

    test('exportText redacts local paths by default', () {
      final service = DebugLogService(isEnabled: () => true);

      service.log(
        category: DebugLogCategory.system,
        event: 'open_file',
        message:
            r'Failed to open C:\Users\Burnt\Documents\GitHub\DACX\video.mp4',
        details: {
          'path': r'C:\Users\Burnt\Documents\GitHub\DACX\video.mp4',
          'cwd': '/home/burnt/dacx',
          'url': 'https://github.com/BurntToasters/Dacx/releases/latest',
        },
      );

      final output = service.exportText();

      expect(output, contains('<path:video.mp4>'));
      expect(output, contains('<path:dacx>'));
      expect(
        output,
        contains('url=https://github.com/BurntToasters/Dacx/releases/latest'),
      );
      expect(
        output,
        isNot(contains(r'C:\Users\Burnt\Documents\GitHub\DACX\video.mp4')),
      );
      expect(output, isNot(contains('/home/burnt/dacx')));
    });

    test('exportText can include raw values when redaction disabled', () {
      final service = DebugLogService(isEnabled: () => true);

      service.log(
        category: DebugLogCategory.system,
        event: 'open_file',
        details: {'path': r'C:\Users\Burnt\Documents\GitHub\DACX\video.mp4'},
      );

      final output = service.exportText(redactSensitive: false);

      expect(
        output,
        contains(r'C:\Users\Burnt\Documents\GitHub\DACX\video.mp4'),
      );
    });

    test('does not capture events when disabled', () {
      final service = DebugLogService(isEnabled: () => false);

      service.log(category: DebugLogCategory.ui, event: 'tap');

      expect(service.entryCount, 0);
      expect(service.exportText(), 'No debug log entries.');
    });

    test('captures error level events when disabled', () {
      final service = DebugLogService(isEnabled: () => false);

      service.log(
        category: DebugLogCategory.error,
        event: 'crash',
        severity: DebugSeverity.error,
      );

      expect(service.entryCount, 1);
      expect(service.entries.first.event, 'crash');
    });

    test('logLazy does not evaluate builders when disabled', () {
      final service = DebugLogService(isEnabled: () => false);
      var messageBuilt = false;
      var detailsBuilt = false;

      service.logLazy(
        category: DebugLogCategory.ui,
        event: 'tap',
        messageBuilder: () {
          messageBuilt = true;
          return 'message';
        },
        detailsBuilder: () {
          detailsBuilt = true;
          return {'key': 'value'};
        },
      );

      expect(messageBuilt, isFalse);
      expect(detailsBuilt, isFalse);
      expect(service.entryCount, 0);
    });

    test('logLazy evaluates builders when enabled', () {
      final service = DebugLogService(isEnabled: () => true);

      service.logLazy(
        category: DebugLogCategory.update,
        event: 'check',
        messageBuilder: () => 'checking',
        detailsBuilder: () => {'channel': 'beta'},
      );

      expect(service.entryCount, 1);
      expect(service.entries.single.message, 'checking');
      expect(service.entries.single.details, {'channel': 'beta'});
    });

    test('exportText redacts a whole-message path', () {
      final service = DebugLogService(isEnabled: () => true);

      service.log(
        category: DebugLogCategory.system,
        event: 'open_file',
        message: '/home/burnt/Videos/movie.mp4',
      );

      final output = service.exportText();

      expect(output, contains('<path:movie.mp4>'));
      expect(output, isNot(contains('/home/burnt/Videos/movie.mp4')));
    });

    test('exportText redacts URL credentials, query, and fragment', () {
      final service = DebugLogService(isEnabled: () => true);

      service.log(
        category: DebugLogCategory.playback,
        event: 'stream_open',
        message:
            'Opening https://user:pass@example.com/live.m3u8?token=secret#frag',
        details: {
          'source': 'https://user:pass@example.com/live.m3u8?token=secret#frag',
        },
      );

      final output = service.exportText();

      expect(
        output,
        contains('https://example.com/live.m3u8?<redacted>#<redacted>'),
      );
      expect(output, isNot(contains('user:pass')));
      expect(output, isNot(contains('token=secret')));
      expect(output, isNot(contains('#frag')));
    });

    test(
      'exportText redacts sensitive keys while ignoring non-sensitive camelCase keys',
      () {
        final service = DebugLogService(isEnabled: () => true);

        service.log(
          category: DebugLogCategory.playback,
          event: 'test_keys',
          details: {
            'userToken': 'secret123',
            'authorName': 'John Doe',
            'auth_type': 'OAuth',
            'user_preference': 'dark',
          },
        );

        final output = service.exportText();

        expect(output, contains('userToken=<redacted>'));
        expect(output, contains('authorName=John Doe'));
        expect(output, contains('auth_type=<redacted>'));
        expect(output, contains('user_preference=<redacted>'));
      },
    );
  });
}
