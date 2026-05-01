import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccentColor {
  blueGrey(Colors.blueGrey, 'Blue Grey'),
  blue(Colors.blue, 'Blue'),
  teal(Colors.teal, 'Teal'),
  purple(Colors.purple, 'Purple'),
  red(Colors.red, 'Red'),
  orange(Colors.orange, 'Orange'),
  green(Colors.green, 'Green'),
  pink(Colors.pink, 'Pink');

  final Color color;
  final String label;
  const AccentColor(this.color, this.label);
}

enum LoopMode {
  none,
  single,
  loop;

  String get label => switch (this) {
    LoopMode.none => 'Off',
    LoopMode.single => 'Single',
    LoopMode.loop => 'Loop',
  };
}

class SettingsService extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static const _kVolume = 'playback_volume';
  static const _kSpeed = 'playback_speed';
  static const _kLoopMode = 'playback_loop_mode';
  static const _kAutoPlay = 'playback_auto_play';
  static const _kTheme = 'appearance_theme';
  static const _kAccent = 'appearance_accent';
  static const _kAlwaysOnTop = 'appearance_always_on_top';
  static const _kRememberWindow = 'appearance_remember_window';
  static const _kWindowWidth = 'window_width';
  static const _kWindowHeight = 'window_height';
  static const _kWindowX = 'window_x';
  static const _kWindowY = 'window_y';
  static const _kRecentFiles = 'recent_files';
  static const _kLastOpenDirectory = 'last_open_directory';
  static const _kUpdateCheck = 'update_check_enabled';
  static const _kLastUpdateCheck = 'update_last_check';
  static const _kHwDec = 'system_hwdec';
  static const _kWindowOpacity = 'window_opacity';
  static const _kWindowBlurEnabled = 'window_blur_enabled';
  static const _kWindowBlurStrength = 'window_blur_strength';
  static const _kExperimentalFeaturesEnabled = 'experimental_features_enabled';
  static const _kLinuxCompositorBlurExperimental =
      'linux_compositor_blur_experimental';
  static const _kDebugModeEnabled = 'debug_mode_enabled';

  static const int maxRecentFiles = 20;

  double get volume => _prefs.getDouble(_kVolume) ?? 100.0;
  set volume(double v) {
    final clamped = v.clamp(0.0, 100.0);
    final current = _prefs.getDouble(_kVolume);
    if (current == clamped) return;
    _prefs.setDouble(_kVolume, clamped);
    notifyListeners();
  }

  double get speed => _prefs.getDouble(_kSpeed) ?? 1.0;
  set speed(double v) {
    _prefs.setDouble(_kSpeed, v);
    notifyListeners();
  }

  LoopMode get loopMode {
    final s = _prefs.getString(_kLoopMode);
    return LoopMode.values.firstWhere(
      (m) => m.name == s,
      orElse: () => LoopMode.none,
    );
  }

  set loopMode(LoopMode m) {
    _prefs.setString(_kLoopMode, m.name);
    notifyListeners();
  }

  bool get autoPlay => _prefs.getBool(_kAutoPlay) ?? true;
  set autoPlay(bool v) {
    _prefs.setBool(_kAutoPlay, v);
    notifyListeners();
  }

  ThemeMode get themeMode {
    final s = _prefs.getString(_kTheme);
    return switch (s) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  set themeMode(ThemeMode m) {
    _prefs.setString(_kTheme, switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
    notifyListeners();
  }

  AccentColor get accentColor {
    final s = _prefs.getString(_kAccent);
    return AccentColor.values.firstWhere(
      (a) => a.name == s,
      orElse: () => AccentColor.blueGrey,
    );
  }

  set accentColor(AccentColor c) {
    _prefs.setString(_kAccent, c.name);
    notifyListeners();
  }

  bool get alwaysOnTop => _prefs.getBool(_kAlwaysOnTop) ?? false;
  set alwaysOnTop(bool v) {
    _prefs.setBool(_kAlwaysOnTop, v);
    notifyListeners();
  }

  bool get rememberWindow => _prefs.getBool(_kRememberWindow) ?? true;
  set rememberWindow(bool v) {
    _prefs.setBool(_kRememberWindow, v);
    notifyListeners();
  }

  Size? get windowSize {
    final w = _prefs.getDouble(_kWindowWidth);
    final h = _prefs.getDouble(_kWindowHeight);
    if (w != null && h != null) return Size(w, h);
    return null;
  }

  void saveWindowSize(Size size) {
    _prefs.setDouble(_kWindowWidth, size.width);
    _prefs.setDouble(_kWindowHeight, size.height);
  }

  Offset? get windowPosition {
    final x = _prefs.getDouble(_kWindowX);
    final y = _prefs.getDouble(_kWindowY);
    if (x != null && y != null) return Offset(x, y);
    return null;
  }

  void saveWindowPosition(Offset pos) {
    _prefs.setDouble(_kWindowX, pos.dx);
    _prefs.setDouble(_kWindowY, pos.dy);
  }

  List<String> get recentFiles {
    return _readStoredRecentFiles();
  }

  String? get lastOpenDirectory {
    final stored = _prefs.getString(_kLastOpenDirectory)?.trim();
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  set lastOpenDirectory(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty || !_isSafeDirectoryPath(normalized)) {
      _prefs.remove(_kLastOpenDirectory);
      return;
    }
    _prefs.setString(_kLastOpenDirectory, normalized);
  }

  bool _isSafeDirectoryPath(String value) {
    if (value.contains('\u0000')) return false;
    final segments = value.replaceAll('\\', '/').split('/');
    if (segments.any((s) => s == '..')) return false;
    try {
      return Directory(value).existsSync();
    } catch (_) {
      return false;
    }
  }

  void addRecentFile(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || normalizedPath.contains('\u0000')) return;
    final files = List<String>.from(recentFiles)..remove(normalizedPath);
    files.insert(0, normalizedPath);
    if (files.length > maxRecentFiles) {
      files.removeRange(maxRecentFiles, files.length);
    }
    _prefs.setString(_kRecentFiles, jsonEncode(files));
    notifyListeners();
  }

  bool pruneRecentFiles({bool notifyListeners = true}) {
    final raw = _prefs.getString(_kRecentFiles);
    if (raw == null) return false;
    final parsed = _decodeStoredRecentFiles(raw);
    final pruned = parsed.where(_recentFilePathExists).toList(growable: false);
    final nextRaw = pruned.isEmpty ? null : jsonEncode(pruned);
    if (nextRaw == raw) return false;

    if (nextRaw == null) {
      _prefs.remove(_kRecentFiles);
    } else {
      _prefs.setString(_kRecentFiles, nextRaw);
    }
    if (notifyListeners) {
      this.notifyListeners();
    }
    return true;
  }

  void clearRecentFiles() {
    _prefs.remove(_kRecentFiles);
    notifyListeners();
  }

  bool get updateCheckEnabled => _prefs.getBool(_kUpdateCheck) ?? true;
  set updateCheckEnabled(bool v) {
    _prefs.setBool(_kUpdateCheck, v);
    notifyListeners();
  }

  int get lastUpdateCheck => _prefs.getInt(_kLastUpdateCheck) ?? 0;
  set lastUpdateCheck(int epoch) {
    _prefs.setInt(_kLastUpdateCheck, epoch);
  }

  bool get shouldCheckForUpdate {
    if (!updateCheckEnabled) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastUpdateCheck) > const Duration(hours: 24).inMilliseconds;
  }

  String get hwDec {
    final stored = _prefs.getString(_kHwDec);
    if (stored != null) return stored;
    // Prefer automatic hardware acceleration on fresh installs.
    return 'auto';
  }

  set hwDec(String v) {
    _prefs.setString(_kHwDec, v);
    notifyListeners();
  }

  double get windowOpacity {
    final stored = _prefs.getDouble(_kWindowOpacity);
    if (stored == null) return 1.0;
    return stored.clamp(0.65, 1.0);
  }

  set windowOpacity(double value) {
    _prefs.setDouble(_kWindowOpacity, value.clamp(0.65, 1.0));
    notifyListeners();
  }

  bool get windowBlurEnabled => _prefs.getBool(_kWindowBlurEnabled) ?? false;

  set windowBlurEnabled(bool value) {
    _prefs.setBool(_kWindowBlurEnabled, value);
    notifyListeners();
  }

  double get windowBlurStrength {
    final stored = _prefs.getDouble(_kWindowBlurStrength);
    if (stored == null) return 0.55;
    return stored.clamp(0.0, 1.0);
  }

  set windowBlurStrength(double value) {
    _prefs.setDouble(_kWindowBlurStrength, value.clamp(0.0, 1.0));
    notifyListeners();
  }

  bool get experimentalFeaturesEnabled =>
      _prefs.getBool(_kExperimentalFeaturesEnabled) ?? false;

  set experimentalFeaturesEnabled(bool value) {
    _prefs.setBool(_kExperimentalFeaturesEnabled, value);
    notifyListeners();
  }

  bool get linuxCompositorBlurExperimental =>
      _prefs.getBool(_kLinuxCompositorBlurExperimental) ?? false;

  set linuxCompositorBlurExperimental(bool value) {
    _prefs.setBool(_kLinuxCompositorBlurExperimental, value);
    notifyListeners();
  }

  bool get debugModeEnabled => _prefs.getBool(_kDebugModeEnabled) ?? false;

  set debugModeEnabled(bool value) {
    _prefs.setBool(_kDebugModeEnabled, value);
    notifyListeners();
  }

  /// Clears all stored preferences and reverts to defaults.
  Future<void> resetAll() async {
    await _prefs.clear();
    notifyListeners();
  }

  List<String> _decodeStoredRecentFiles(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  List<String> _readStoredRecentFiles() {
    final raw = _prefs.getString(_kRecentFiles);
    if (raw == null) return const [];
    return _decodeStoredRecentFiles(raw);
  }

  bool _recentFilePathExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
