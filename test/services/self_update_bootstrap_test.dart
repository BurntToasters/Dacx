import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';

void main() {
  // Legacy PowerShell bootstrap scripts were replaced by dacx-update-helper.exe.
  // Keep this file as a pointer so old imports/docs don't leave a silent gap.
  test('native helper launch helpers are available', () {
    expect(
      SelfUpdateService.buildWindowsHelperLaunchCommandLine('abcd'),
      contains('-EncodedCommand abcd'),
    );
  });
}
