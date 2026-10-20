import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class PreferencesRecovery {
  static const storeFileName = 'shared_preferences.json';

  static bool isDecodeError(Object e) {
    if (e is FormatException) return true;
    final text = e.toString();
    return text.contains('FormatException');
  }

  static Future<SharedPreferences> load({
    Future<SharedPreferences> Function()? loader,
    Future<File?> Function()? storeFile,
    void Function(String movedTo)? onRecovered,
  }) async {
    final load = loader ?? SharedPreferences.getInstance;
    try {
      return await load();
    } catch (first) {
      if (isDecodeError(first)) {
        return _recover(first, load, storeFile, onRecovered);
      }
      try {
        return await load();
      } catch (second) {
        if (isDecodeError(second)) {
          return _recover(second, load, storeFile, onRecovered);
        }
        rethrow;
      }
    }
  }

  static Future<SharedPreferences> _recover(
    Object original,
    Future<SharedPreferences> Function() load,
    Future<File?> Function()? storeFile,
    void Function(String movedTo)? onRecovered,
  ) async {
    final file = await (storeFile ?? defaultStoreFile)();
    if (file == null || !file.existsSync()) throw original;
    final movedTo =
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
    file.renameSync(movedTo);
    onRecovered?.call(movedTo);
    try {
      return await load();
    } catch (_) {
      return SharedPreferences.getInstance();
    }
  }

  static Future<File?> defaultStoreFile() async {
    try {
      final String? directory;
      if (Platform.isWindows) {
        directory = await PathProviderWindows().getApplicationSupportPath();
      } else if (Platform.isLinux) {
        directory = await PathProviderLinux().getApplicationSupportPath();
      } else {
        return null;
      }
      if (directory == null || directory.isEmpty) return null;
      return File(p.join(directory, storeFileName));
    } catch (_) {
      return null;
    }
  }
}
