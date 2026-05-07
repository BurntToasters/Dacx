import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../debug_agent_log.dart';

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

  // #region agent log
  agentDebugNdjson(
    location: 'shared_preferences_bootstrap.dart:dacxRepair',
    message: 'prefs_repair_started',
    hypothesisId: 'H_PREFS',
    data: const {},
  );
  // #endregion

  final file = dacxTryWindowsSharedPreferencesFile();
  if (file == null) {
    // #region agent log
    agentDebugNdjson(
      location: 'shared_preferences_bootstrap.dart:dacxRepair',
      message: 'prefs_json_path_unavailable',
      hypothesisId: 'H_PREFS',
      data: const {},
    );
    // #endregion
    return;
  }

  try {
    if (!file.existsSync()) {
      // #region agent log
      agentDebugNdjson(
        location: 'shared_preferences_bootstrap.dart:dacxRepair',
        message: 'prefs_json_absent',
        hypothesisId: 'H_PREFS',
        data: const {},
      );
      // #endregion
      return;
    }

    final len = await file.length();
    // #region agent log
    agentDebugNdjson(
      location: 'shared_preferences_bootstrap.dart:dacxRepair',
      message: 'prefs_json_stats',
      hypothesisId: 'H_PREFS',
      data: {'bytes': len},
    );
    // #endregion

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
  } catch (e) {
    // #region agent log
    agentDebugNdjson(
      location: 'shared_preferences_bootstrap.dart:dacxRepair',
      message: 'prefs_repair_skipped',
      hypothesisId: 'H_PREFS',
      data: {'error': e.toString()},
    );
    // #endregion
  }
}

Future<void> _quarantinePrefsFile(File file, String reason) async {
  try {
    final bak =
        '${file.path}.$reason.${DateTime.now().millisecondsSinceEpoch}.bak';
    await file.rename(bak);
    // #region agent log
    agentDebugNdjson(
      location: 'shared_preferences_bootstrap.dart:dacxRepair',
      message: 'prefs_json_quarantined',
      hypothesisId: 'H_PREFS',
      data: {'reason': reason},
    );
    // #endregion
  } catch (e) {
    // #region agent log
    agentDebugNdjson(
      location: 'shared_preferences_bootstrap.dart:dacxRepair',
      message: 'prefs_json_quarantine_failed',
      hypothesisId: 'H_PREFS',
      data: {'reason': reason, 'error': e.toString()},
    );
    // #endregion
  }
}
