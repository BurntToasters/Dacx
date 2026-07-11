import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/windows_shell_service.dart';

void main() {
  test('Windows shell method names are frozen', () {
    expect(WindowsShellService.updateJumpListMethod, 'updateJumpList');
    expect(WindowsShellService.setTaskbarProgressMethod, 'setTaskbarProgress');
  });
}
