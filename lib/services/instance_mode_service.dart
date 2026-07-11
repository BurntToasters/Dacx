import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class InstanceModeService {
  static const String _flagFileName = 'allow_multi_instance';
  static const String newInstanceFlag = '--new-instance';
  static const windowMethodChannelName = 'run.rosie.dacx/window/methods';

  /// Native → Flutter: macOS application menu “Check for Updates…”.
  static const checkForUpdatesMethod = 'checkForUpdates';

  /// Native → Flutter: macOS Preferences… (⌘,).
  static const openPreferencesMethod = 'openPreferences';

  /// Native → Flutter: macOS File → Open….
  static const openFileMethod = 'openFile';

  /// Native → Flutter: macOS File → Open URL….
  static const openUrlMethod = 'openUrl';

  /// Native → Flutter: macOS File → Open Recent item (path argument).
  static const openRecentMethod = 'openRecent';

  /// Native → Flutter: request recent paths to rebuild Open Recent submenu.
  static const getRecentFilesMethod = 'getRecentFiles';

  static const MethodChannel _windowMethodChannel = MethodChannel(
    windowMethodChannelName,
  );

  static String? _cachedFlagDir;
  static String? _flagDirOverride;

  @visibleForTesting
  static void setFlagDirForTesting(String? dir) {
    _flagDirOverride = dir;
    _cachedFlagDir = null;
  }

  static String _flagDir() {
    final override = _flagDirOverride;
    if (override != null) return override;
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

  static Future<bool> setAllowMultipleInstances(bool enabled) async {
    try {
      final path = flagFilePath();
      final file = File(path);
      if (enabled) {
        await Directory(p.dirname(path)).create(recursive: true);
        await file.writeAsString('1', flush: true);
      } else if (file.existsSync()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: setAllowMultipleInstances failed: $e');
      }
      return false;
    }
  }

  static Future<bool> openNewWindow() async {
    if (isAllowMultipleInstancesEnabled()) {
      if (kDebugMode) {
        debugPrint(
          'Dacx: openNewWindow → spawnNewInstance (allow_multi_instance flag set)',
        );
      }
      return spawnNewInstance();
    }
    if (Platform.isWindows || Platform.isLinux) {
      if (kDebugMode) {
        debugPrint(
          'Dacx: openNewWindow → spawnNewInstance (separate process on ${Platform.operatingSystem})',
        );
      }
      return spawnNewInstance();
    }
    if (Platform.isMacOS) {
      try {
        final opened = await _windowMethodChannel.invokeMethod<bool>(
          'openNewWindow',
        );
        if (opened == true) {
          if (kDebugMode) {
            debugPrint('Dacx: openNewWindow → in-process native bridge');
          }
          return true;
        }
      } on MissingPluginException catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: native openNewWindow bridge missing: $e');
        }
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: native openNewWindow failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint('Dacx: openNewWindow → spawnNewInstance (fallback)');
    }
    return spawnNewInstance();
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
