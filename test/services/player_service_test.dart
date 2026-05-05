// PlayerService is a thin guarded wrapper over media_kit's Player. The
// Player constructor + dispose require the native libmpv binary to be
// resolvable, which it isn't in a headless `flutter test` VM, so we
// deliberately scope this file to value-semantics that don't touch the
// native layer.
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/player_service.dart';

void main() {
  group('PlayerErrorEvent', () {
    test('toString includes operation and error', () {
      final ev = PlayerErrorEvent('open', 'boom', StackTrace.empty);
      final s = ev.toString();
      expect(s, contains('open'));
      expect(s, contains('boom'));
    });

    test('preserves all three fields verbatim', () {
      final st = StackTrace.current;
      final err = Exception('x');
      final ev = PlayerErrorEvent('seek', err, st);
      expect(ev.operation, 'seek');
      expect(ev.error, same(err));
      expect(ev.stackTrace, same(st));
    });

    test('distinct operations produce distinct toString output', () {
      final a = PlayerErrorEvent('open', 'e', StackTrace.empty);
      final b = PlayerErrorEvent('seek', 'e', StackTrace.empty);
      expect(a.toString(), isNot(equals(b.toString())));
    });
  });
}
