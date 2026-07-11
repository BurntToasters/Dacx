import 'dart:io';

import 'package:path/path.dart' as p;

/// How Dacx was installed on Linux — drives update guidance copy.
enum LinuxInstallKind { flatpak, appImage, debOrRpm, portable, unknown }

abstract final class LinuxInstallDetector {
  /// Detects install type from environment and executable path.
  ///
  /// When [environment] or [resolvedExecutable] are passed explicitly (tests),
  /// the [Platform.isLinux] gate is skipped so detection logic stays unit-testable
  /// on other hosts.
  static LinuxInstallKind detect({
    Map<String, String>? environment,
    String? resolvedExecutable,
  }) {
    final testingOverrides = environment != null || resolvedExecutable != null;
    if (!testingOverrides && !Platform.isLinux) {
      return LinuxInstallKind.unknown;
    }
    final env = environment ?? Platform.environment;
    if ((env['FLATPAK_ID'] ?? '').trim().isNotEmpty) {
      return LinuxInstallKind.flatpak;
    }
    if ((env['APPIMAGE'] ?? '').trim().isNotEmpty) {
      return LinuxInstallKind.appImage;
    }
    final exe = (resolvedExecutable ?? Platform.resolvedExecutable).trim();
    if (exe.isEmpty) return LinuxInstallKind.unknown;
    final lower = exe.toLowerCase();
    if (lower.endsWith('.appimage') || lower.contains('/appimagekit_')) {
      return LinuxInstallKind.appImage;
    }
    // Distro packages typically land under /usr.
    final normalized = p.normalize(exe);
    if (normalized.startsWith('/usr/') ||
        normalized.startsWith('/bin/') ||
        normalized.startsWith('/sbin/')) {
      return LinuxInstallKind.debOrRpm;
    }
    return LinuxInstallKind.portable;
  }

  static bool get isFlatpak {
    if (!Platform.isLinux) return false;
    return (Platform.environment['FLATPAK_ID'] ?? '').trim().isNotEmpty;
  }
}
