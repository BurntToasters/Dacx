import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/idle_inhibit_service.dart';

void main() {
  group('IdleInhibitService', () {
    test('mprisDesktopEntry is non-empty', () {
      final entry = IdleInhibitService.mprisDesktopEntry();
      expect(entry, isNotEmpty);
    });

    test('parseUint32ReplyForTest reads cookie', () {
      expect(
        IdleInhibitService.parseUint32ReplyForTest(
          'method return time=1 sender=:1.0 -> dest=:1.1\n   uint32 42\n',
        ),
        42,
      );
      expect(IdleInhibitService.parseUint32ReplyForTest('nope'), isNull);
    });

    test('setIdleInhibitMethod constant is frozen', () {
      expect(IdleInhibitService.setIdleInhibitMethod, 'setIdleInhibit');
    });

    test('Linux D-Bus Inhibit reply shape is uint32 cookie', () async {
      final response = DBusMethodSuccessResponse([DBusUint32(7)]);
      expect(response.returnValues.single.asUint32(), 7);
      expect(DBusSignature('u'), response.returnValues.single.signature);
    });
  });
}
