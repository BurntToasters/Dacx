import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Roaming prefs path for DACX on Windows (matches `windows/runner/Runner.rc`
/// CompanyName + ProductName used by path_provider_windows).
File? dacxTryWindowsSharedPreferencesFile() {
  if (!Platform.isWindows) return null;
  final appdata = Platform.environment['APPDATA'];
  if (appdata == null || appdata.isEmpty) return null;
  return File(p.join(appdata, 'run.rosie', 'Dacx', 'shared_preferences.json'));
}

/// Quarantines a corrupt or oversized legacy prefs JSON so the next
/// [SharedPreferences.getInstance] can create a fresh store.
Future<void> dacxRepairSharedPreferencesFileBestEffort() async {
  if (!Platform.isWindows) return;

  final file = dacxTryWindowsSharedPreferencesFile();
  if (file == null) return;

  try {
    if (!file.existsSync()) return;

    final len = await file.length();
    const maxBytes = 12 * 1024 * 1024;
    if (len > maxBytes) {
      await _quarantinePrefsFile(file, 'oversized');
      return;
    }

    final text = await file.readAsString();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        await _quarantinePrefsFile(file, 'not_map');
        return;
      }
      for (final key in decoded.keys) {
        if (key is! String) {
          await _quarantinePrefsFile(file, 'bad_keys');
          return;
        }
      }
    } catch (_) {
      await _quarantinePrefsFile(file, 'json_decode');
    }
  } catch (_) {}
}

Future<void> _quarantinePrefsFile(File file, String reason) async {
  try {
    final bak =
        '${file.path}.$reason.${DateTime.now().millisecondsSinceEpoch}.bak';
    await file.rename(bak);
  } catch (_) {}
}
