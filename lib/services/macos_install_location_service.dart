import 'dart:io';

abstract final class MacosInstallLocationService {
  static const expectedAppPath = '/Applications/Dacx.app';

  static bool shouldWarnForCurrentApp() {
    if (!Platform.isMacOS) return false;
    return shouldWarnForExecutablePath(Platform.resolvedExecutable);
  }

  static bool shouldWarnForExecutablePath(String executablePath) {
    final appPath = appBundlePathForExecutable(executablePath);
    if (appPath == null) return false;
    return appPath != expectedAppPath;
  }

  static String? appBundlePathForExecutable(String executablePath) {
    const marker = '.app/Contents/MacOS/';
    final markerIndex = executablePath.indexOf(marker);
    if (markerIndex < 0) return null;
    return executablePath.substring(0, markerIndex + '.app'.length);
  }
}
