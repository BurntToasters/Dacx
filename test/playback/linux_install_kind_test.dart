import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/linux_install_kind.dart';

void main() {
  group('LinuxInstallDetector', () {
    test('prefers Flatpak env', () {
      expect(
        LinuxInstallDetector.detect(
          environment: {'FLATPAK_ID': 'run.rosie.dacx'},
          resolvedExecutable: '/usr/bin/dacx',
        ),
        LinuxInstallKind.flatpak,
      );
    });

    test('detects AppImage env and suffix', () {
      expect(
        LinuxInstallDetector.detect(
          environment: {'APPIMAGE': '/home/u/Dacx.AppImage'},
          resolvedExecutable: '/tmp/.mount_Dacx/usr/bin/dacx',
        ),
        LinuxInstallKind.appImage,
      );
      expect(
        LinuxInstallDetector.detect(
          environment: const {},
          resolvedExecutable: '/home/u/Downloads/Dacx.AppImage',
        ),
        LinuxInstallKind.appImage,
      );
    });

    test('detects /usr package installs', () {
      expect(
        LinuxInstallDetector.detect(
          environment: const {},
          resolvedExecutable: '/usr/bin/dacx',
        ),
        LinuxInstallKind.debOrRpm,
      );
    });

    test('detects /opt/dacx package installs', () {
      expect(
        LinuxInstallDetector.detect(
          environment: const {},
          resolvedExecutable: '/opt/dacx/dacx',
        ),
        LinuxInstallKind.debOrRpm,
      );
      expect(
        LinuxInstallDetector.detect(
          environment: const {},
          resolvedExecutable: '/opt/dacx/lib/dacx',
        ),
        LinuxInstallKind.debOrRpm,
      );
    });

    test('other paths are portable', () {
      expect(
        LinuxInstallDetector.detect(
          environment: const {},
          resolvedExecutable: '/home/u/Downloads/dacx/dacx',
        ),
        LinuxInstallKind.portable,
      );
    });
  });
}
