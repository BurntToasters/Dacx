import 'dart:io';

import 'package:path/path.dart' as p;

abstract final class WindowsSystemPaths {
  static final p.Context _windowsPath = p.Context(style: p.Style.windows);

  static String systemRoot({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final root = (env['SystemRoot'] ?? env['SYSTEMROOT'] ?? '').trim();
    return root.isNotEmpty ? root : r'C:\Windows';
  }

  static String powershell({Map<String, String>? environment}) =>
      _windowsPath.join(
        systemRoot(environment: environment),
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );

  static String msiexec({Map<String, String>? environment}) => _windowsPath
      .join(systemRoot(environment: environment), 'System32', 'msiexec.exe');
}
