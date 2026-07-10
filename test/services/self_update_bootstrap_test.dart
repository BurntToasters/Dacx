import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';

void main() {
  group('SelfUpdateService.buildWindowsBootstrapPowerShellScript', () {
    test(
      'embeds watchdog script path, pid, msi path, thumbprint, and sha256',
      () {
        const scriptPath =
            r'C:\Users\dev\AppData\Local\Dacx\updates\watchdog.ps1';
        const msiPath =
            r'C:\Users\dev\AppData\Local\Dacx\updates\Dacx-Windows-x64.msi';
        const thumbprint = 'ABCD1234EF567890';
        const sha256 =
            'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

        final script = SelfUpdateService.buildWindowsBootstrapPowerShellScript(
          scriptPath: scriptPath,
          dacxPid: 4242,
          msiPath: msiPath,
          thumbprint: thumbprint,
          sha256: sha256,
        );

        expect(script, contains('Win32_Process'));
        expect(script, contains('Invoke-CimMethod'));
        expect(script, contains('watchdog.ps1'));
        expect(script, contains('4242'));
        expect(script, contains('Dacx-Windows-x64.msi'));
        expect(script, contains(thumbprint));
        expect(script, contains(sha256));
        expect(script, contains('bootstrap.log'));
      },
    );

    test('escapes embedded double quotes in paths', () {
      final script = SelfUpdateService.buildWindowsBootstrapPowerShellScript(
        scriptPath: r'C:\temp\"quoted"\watchdog.ps1',
        dacxPid: 1,
        msiPath: r'C:\temp\"quoted"\Dacx.msi',
        thumbprint: 'THUMB',
        sha256: 'a' * 64,
      );

      expect(script, isNot(contains(r'C:\temp\"quoted"')));
      expect(script, contains(r'\"'));
    });
  });
}
