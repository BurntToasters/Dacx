import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/windows_system_paths.dart';

void main() {
  test('WindowsSystemPaths resolves PowerShell under System32', () {
    expect(
      WindowsSystemPaths.powershell(environment: {'SystemRoot': r'C:\Windows'}),
      r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
    );
  });

  test('WindowsSystemPaths resolves msiexec under System32', () {
    expect(
      WindowsSystemPaths.msiexec(environment: {'SystemRoot': r'C:\Windows'}),
      r'C:\Windows\System32\msiexec.exe',
    );
  });
}
