import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/macos_install_location_service.dart';

void main() {
  group('MacosInstallLocationService', () {
    test('accepts Dacx in Applications', () {
      expect(
        MacosInstallLocationService.shouldWarnForExecutablePath(
          '/Applications/Dacx.app/Contents/MacOS/Dacx',
        ),
        isFalse,
      );
    });

    test('warns for packaged app outside Applications', () {
      expect(
        MacosInstallLocationService.shouldWarnForExecutablePath(
          '/Users/dev/Downloads/Dacx.app/Contents/MacOS/Dacx',
        ),
        isTrue,
      );
    });

    test('does not warn for non-app debug executable', () {
      expect(
        MacosInstallLocationService.shouldWarnForExecutablePath(
          '/Users/dev/Documents/GitHub/Dacx/build/macos/Build/Products/Debug/Dacx',
        ),
        isFalse,
      );
    });
  });
}
