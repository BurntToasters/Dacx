import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/idle_inhibit_service.dart';

void main() {
  group('IdleInhibitService', () {
    test('mprisDesktopEntry is non-empty basename', () {
      final entry = IdleInhibitService.mprisDesktopEntry();
      expect(entry, isNotEmpty);
      expect(entry.contains('.desktop'), isFalse);
    });

    test('parseUint32Reply extracts cookie', () {
      // ignore: invalid_use_of_visible_for_testing_member
      expect(
        IdleInhibitService.parseUint32ReplyForTest(
          'method return time=1\n   uint32 42\n',
        ),
        42,
      );
      expect(IdleInhibitService.parseUint32ReplyForTest('nope'), isNull);
    });
  });
}
