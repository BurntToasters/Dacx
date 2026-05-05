import 'dart:io';

import 'package:path/path.dart' as p;

class InstanceModeService {
  static const String _flagFileName = 'allow_multi_instance';
  static const String newInstanceFlag = '--new-instance';

  static String? _cachedFlagDir;

  static String _flagDir() {
    final cached = _cachedFlagDir;
    if (cached != null) return cached;
    final env = Platform.environment;
    String? dir;
    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        dir = p.join(home, 'Library', 'Application Support', 'Dacx');
      }
    } else if (Platform.isLinux) {
      final xdg = env['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        dir = p.join(xdg, 'dacx');
      } else {
        final home = env['HOME'];
        if (home != null && home.isNotEmpty) {
          dir = p.join(home, '.config', 'dacx');
        }
      }
    } else if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty) {
        dir = p.join(local, 'Dacx');
      }
    }
    dir ??= Directory.systemTemp.path;
    _cachedFlagDir = dir;
    return dir;
  }

  static String flagFilePath() => p.join(_flagDir(), _flagFileName);

  static bool isAllowMultipleInstancesEnabled() {
    try {
      return File(flagFilePath()).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAllowMultipleInstances(bool enabled) async {
    try {
      final path = flagFilePath();
      final file = File(path);
      if (enabled) {
        await Directory(p.dirname(path)).create(recursive: true);
        await file.writeAsString('1', flush: true);
      } else if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<bool> spawnNewInstance({String? filePath}) async {
    try {
      final exe = Platform.resolvedExecutable;
      if (Platform.isMacOS) {
        final bundlePath = _macAppBundlePath(exe);
        final args = <String>['-n'];
        if (bundlePath != null) {
          args.addAll(['-a', bundlePath]);
        } else {
          args.add(exe);
        }
        args.add('--args');
        args.add(newInstanceFlag);
        if (filePath != null && filePath.isNotEmpty) args.add(filePath);
        await Process.start('open', args, mode: ProcessStartMode.detached);
        return true;
      }
      final args = <String>[newInstanceFlag];
      if (filePath != null && filePath.isNotEmpty) args.add(filePath);
      await Process.start(exe, args, mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _macAppBundlePath(String executablePath) {
    const marker = '.app/Contents/MacOS/';
    final idx = executablePath.indexOf(marker);
    if (idx < 0) return null;
    return executablePath.substring(0, idx + '.app'.length);
  }
}
