import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playable_source.dart';
import '../models/update_channel.dart';
import 'instance_mode_service.dart';

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

  SettingsService(this._prefs) {
    _runMigrationsIfNeeded();
  }

  @override
  void dispose() {
    _resumePersistTimer?.cancel();
    _resumePersistTimer = null;
    _persistResumePositionsToPrefs();
    super.dispose();
  }

  /// Writes any pending resume-position cache to disk immediately.
  void flushResumePositions() {
    _resumePersistTimer?.cancel();
    _resumePersistTimer = null;
    _persistResumePositionsToPrefs();
  }

  List<double>? _eqBandsCache;
  Map<String, List<String>>? _keybindsCache;
  Map<String, _ResumeEntry>? _resumePositionsCache;
  Timer? _resumePersistTimer;
  int _resumeAccessCounter = 0;
  static const Duration _resumePersistDebounce = Duration(milliseconds: 800);

  /// Bump this and append a new entry to [_migrations] whenever a stored
  /// settings key is added/removed/renamed/retyped in a way that needs to
  /// transform existing data on disk.
  ///
  /// Each migration is a synchronous function `(prefs) => void` that takes
  /// the schema from version `i` to version `i + 1`, where `i` is the
  /// migration's index in [_migrations].
  static const int currentSchemaVersion = 2;
  static const String _kSchemaVersion = 'settings_schema_version';

  /// `_migrations[i]` upgrades from version `i` to version `i + 1`.
  /// Adding a new migration: append, then bump [currentSchemaVersion] to
  /// match the new list length.
  static final List<void Function(SharedPreferences)> _migrations =
      <void Function(SharedPreferences)>[
        // 0 -> 1: baseline. No transform; just stamps the schema version on
        // existing installs so future migrations have a known starting point.
        (prefs) {},
        // 1 -> 2: convert resume_positions_v1 (Map<path,int>) into
        // resume_positions_v2 (Map<path,{p,t}>). Existing entries are stamped
        // with the current wall-clock so subsequent LRU eviction has a starting
        // ordering; v1 key is removed.
        (prefs) {
          final raw = prefs.getString('resume_positions_v1');
          if (raw == null) return;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is! Map) {
              prefs.remove('resume_positions_v1');
              return;
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            final upgraded = <String, Map<String, int>>{};
            decoded.forEach((key, value) {
              if (key is String && value is int && value > 0) {
                upgraded[key] = {'p': value, 't': now};
              }
            });
            if (upgraded.isNotEmpty) {
              prefs.setString('resume_positions_v2', jsonEncode(upgraded));
            }
            prefs.remove('resume_positions_v1');
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Dacx: resume_positions_v1 migration failed: $e');
            }
            prefs.remove('resume_positions_v1');
          }
        },
      ];

  void _runMigrationsIfNeeded() {
    // Fresh install: no settings keys have been written yet — stamp the
    // current schema version and skip running any migrations.
    final hasAnyKey = _prefs.getKeys().isNotEmpty;
    final stored = _prefs.getInt(_kSchemaVersion);
    if (!hasAnyKey) {
      _prefs.setInt(_kSchemaVersion, currentSchemaVersion);
      return;
    }
    final from = stored ?? 0;
    if (from >= currentSchemaVersion) return;
    for (var i = from; i < currentSchemaVersion; i++) {
      if (i < _migrations.length) {
        _migrations[i](_prefs);
      }
    }
    _prefs.setInt(_kSchemaVersion, currentSchemaVersion);
  }

  int get schemaVersion =>
      _prefs.getInt(_kSchemaVersion) ?? currentSchemaVersion;

  static const _kVolume = 'playback_volume';
  static const _kSpeed = 'playback_speed';
  static const _kLoopMode = 'playback_loop_mode';
  static const _kUpdateChannel = 'update_channel';
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
  static const _kFileBookmarks = 'file_bookmarks_v1';
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
  static const _kEqEnabled = 'eq_enabled';
  static const _kEqPreset = 'eq_preset';
  static const _kEqBands = 'eq_bands';
  static const _kScreenshotDir = 'screenshot_dir';
  static const _kScreenshotFormat = 'screenshot_format';
  static const _kOsdEnabled = 'osd_enabled';
  static const _kSeekPreviewEnabled = 'seek_preview_enabled';
  static const _kAudioWaveformEnabled = 'audio_waveform_enabled';
  static const _kMultiAudioMix = 'multi_audio_mix';
  static const _kMediaSession = 'media_session_enabled';
  static const _kKeybinds = 'keybinds_v1';
  static const _kResumeEnabled = 'resume_playback_enabled';
  static const _kResumePositions = 'resume_positions_v2';
  static const _kPlaylistShuffle = 'playlist_shuffle';
  static const _kAllowMultipleInstances = 'allow_multiple_instances';

  /// Persisted preference keys. Renaming requires a migration; keep in sync with
  /// [test/services/frozen_identifiers_test.dart].
  static const Set<String> frozenPreferenceKeys = {
    _kSchemaVersion,
    _kVolume,
    _kSpeed,
    _kLoopMode,
    _kUpdateChannel,
    _kAutoPlay,
    _kTheme,
    _kAccent,
    _kAlwaysOnTop,
    _kRememberWindow,
    _kWindowWidth,
    _kWindowHeight,
    _kWindowX,
    _kWindowY,
    _kRecentFiles,
    _kFileBookmarks,
    _kLastOpenDirectory,
    _kUpdateCheck,
    _kLastUpdateCheck,
    _kHwDec,
    _kWindowOpacity,
    _kWindowBlurEnabled,
    _kWindowBlurStrength,
    _kExperimentalFeaturesEnabled,
    _kLinuxCompositorBlurExperimental,
    _kDebugModeEnabled,
    _kEqEnabled,
    _kEqPreset,
    _kEqBands,
    _kScreenshotDir,
    _kScreenshotFormat,
    _kOsdEnabled,
    _kSeekPreviewEnabled,
    _kAudioWaveformEnabled,
    _kMultiAudioMix,
    _kMediaSession,
    _kKeybinds,
    _kResumeEnabled,
    _kResumePositions,
    _kPlaylistShuffle,
    _kAllowMultipleInstances,
  };

  /// Maximum playback-resume entries kept (per file). LRU pruned.
  static const int maxResumeEntries = 100;

  /// Minimum elapsed seconds before a resume position is recorded.
  static const int resumeMinElapsedSeconds = 30;

  /// Tail offset from end-of-track that suppresses resume save (treat as fully watched).
  static const int resumeTailIgnoreSeconds = 15;

  static const int maxRecentFiles = 20;
  static const int eqBandCount = 10;
  static const List<int> eqBandFrequencies = [
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

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

  UpdateChannel get updateChannel {
    final s = _prefs.getString(_kUpdateChannel);
    return UpdateChannel.values.firstWhere(
      (c) => c.name == s,
      orElse: () => UpdateChannel.auto,
    );
  }

  set updateChannel(UpdateChannel c) {
    _prefs.setString(_kUpdateChannel, c.name);
    notifyListeners();
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: directory path check failed: $e');
      }
      return false;
    }
  }

  /// Looser variant of [_isSafeDirectoryPath] for individual file paths
  /// stored in recents / resume-position records. Files come and go on
  /// disk so we don't gate on existence here, but we still reject obvious
  /// path-traversal payloads and embedded NULs to keep the JSON store
  /// hygienic.
  bool _isSafeFilePath(String value) {
    if (value.isEmpty) return false;
    if (value.contains('\u0000')) return false;
    if (PlayableSource.isSupportedUrl(value)) {
      return PlayableSource.isDisplaySafeUrl(value);
    }
    final segments = value.replaceAll('\\', '/').split('/');
    if (segments.any((s) => s == '..')) return false;
    return true;
  }

  void addRecentFile(String path) {
    final normalizedPath = path.trim();
    if (!_isSafeFilePath(normalizedPath)) return;
    final files = List<String>.from(recentFiles)..remove(normalizedPath);
    files.insert(0, normalizedPath);
    if (files.length > maxRecentFiles) {
      files.removeRange(maxRecentFiles, files.length);
    }
    _prefs.setString(_kRecentFiles, jsonEncode(files));
    _pruneBookmarksToList(files);
    notifyListeners();
  }

  Map<String, String> _readBookmarkMap() {
    final raw = _prefs.getString(_kFileBookmarks);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, String>{};
        decoded.forEach((k, v) {
          if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
            result[k] = v;
          }
        });
        return result;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: file bookmarks decode failed: $e');
      }
    }
    return <String, String>{};
  }

  void _writeBookmarkMap(Map<String, String> map) {
    if (map.isEmpty) {
      _prefs.remove(_kFileBookmarks);
    } else {
      _prefs.setString(_kFileBookmarks, jsonEncode(map));
    }
  }

  String? fileBookmark(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    return _readBookmarkMap()[normalized];
  }

  void setFileBookmark(String path, String bookmark) {
    final normalized = path.trim();
    if (!_isSafeFilePath(normalized) || bookmark.isEmpty) return;
    final map = _readBookmarkMap();
    map[normalized] = bookmark;
    _writeBookmarkMap(map);
  }

  void removeFileBookmark(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final map = _readBookmarkMap();
    if (map.remove(normalized) != null) {
      _writeBookmarkMap(map);
    }
  }

  void _pruneBookmarksToList(List<String> keep) {
    final map = _readBookmarkMap();
    if (map.isEmpty) return;
    final keepSet = keep.toSet();
    map.removeWhere((k, _) => !keepSet.contains(k));
    _writeBookmarkMap(map);
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
    _pruneBookmarksToList(pruned);
    if (notifyListeners) {
      this.notifyListeners();
    }
    return true;
  }

  void clearRecentFiles() {
    _prefs.remove(_kRecentFiles);
    _prefs.remove(_kFileBookmarks);
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

  /// Minimum UI translucency when blur is on (Flutter shell alpha).
  static const double windowOpacityMin = 0.55;

  double get windowOpacity {
    final stored = _prefs.getDouble(_kWindowOpacity);
    if (stored == null) return 1.0;
    return stored.clamp(windowOpacityMin, 1.0);
  }

  set windowOpacity(double value) {
    _prefs.setDouble(_kWindowOpacity, value.clamp(windowOpacityMin, 1.0));
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

  bool get eqEnabled => _prefs.getBool(_kEqEnabled) ?? false;
  set eqEnabled(bool v) {
    _prefs.setBool(_kEqEnabled, v);
    notifyListeners();
  }

  String get eqPreset => _prefs.getString(_kEqPreset) ?? 'flat';
  set eqPreset(String v) {
    _prefs.setString(_kEqPreset, v);
    notifyListeners();
  }

  /// 10 gain values in dB (-12..+12), one per band.
  List<double> get eqBands {
    final cached = _eqBandsCache;
    if (cached != null) return List<double>.unmodifiable(cached);
    final raw = _prefs.getString(_kEqBands);
    List<double> result;
    if (raw == null) {
      result = List<double>.filled(eqBandCount, 0);
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          result = List<double>.filled(eqBandCount, 0);
        } else {
          final out = decoded
              .whereType<num>()
              .map((n) => n.toDouble().clamp(-12.0, 12.0))
              .toList();
          while (out.length < eqBandCount) {
            out.add(0);
          }
          result = out.sublist(0, eqBandCount);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: EQ bands decode failed: $e');
        }
        result = List<double>.filled(eqBandCount, 0);
      }
    }
    _eqBandsCache = result;
    return List<double>.unmodifiable(result);
  }

  set eqBands(List<double> values) {
    final clamped = List<double>.generate(
      eqBandCount,
      (i) => i < values.length ? values[i].clamp(-12.0, 12.0).toDouble() : 0.0,
    );
    _eqBandsCache = clamped;
    _prefs.setString(_kEqBands, jsonEncode(clamped));
    notifyListeners();
  }

  String? get screenshotDir {
    final v = _prefs.getString(_kScreenshotDir)?.trim();
    if (v == null || v.isEmpty) return null;
    if (!_isSafeDirectoryPath(v)) return null;
    return v;
  }

  set screenshotDir(String? value) {
    final n = value?.trim() ?? '';
    if (n.isEmpty || !_isSafeDirectoryPath(n)) {
      _prefs.remove(_kScreenshotDir);
    } else {
      _prefs.setString(_kScreenshotDir, n);
    }
    notifyListeners();
  }

  String get screenshotFormat {
    final v = _prefs.getString(_kScreenshotFormat);
    if (v == 'png' || v == 'jpg') return v!;
    return 'png';
  }

  set screenshotFormat(String v) {
    if (v != 'png' && v != 'jpg') return;
    _prefs.setString(_kScreenshotFormat, v);
    notifyListeners();
  }

  bool get osdEnabled => _prefs.getBool(_kOsdEnabled) ?? true;
  set osdEnabled(bool v) {
    _prefs.setBool(_kOsdEnabled, v);
    notifyListeners();
  }

  bool get seekPreviewEnabled => _prefs.getBool(_kSeekPreviewEnabled) ?? false;
  set seekPreviewEnabled(bool v) {
    if (seekPreviewEnabled == v) return;
    _prefs.setBool(_kSeekPreviewEnabled, v);
    notifyListeners();
  }

  /// Audio spectrum visualizer. Experimental — preference is preserved but
  /// reported as `false` when Experimental Features is off (same pattern as
  /// [multiAudioMix]).
  bool get audioWaveformEnabled {
    if (!experimentalFeaturesEnabled) return false;
    return _prefs.getBool(_kAudioWaveformEnabled) ?? false;
  }

  set audioWaveformEnabled(bool v) {
    _prefs.setBool(_kAudioWaveformEnabled, v);
    notifyListeners();
  }

  /// Mix all audio tracks into one output via mpv `lavfi-complex`.
  /// Marked experimental; the stored preference is preserved but
  /// reported as `false` whenever Experimental Features is disabled,
  /// so all consumers automatically get the safe default without
  /// needing to re-check the experimental flag themselves.
  bool get multiAudioMix {
    if (!experimentalFeaturesEnabled) return false;
    return _prefs.getBool(_kMultiAudioMix) ?? false;
  }

  set multiAudioMix(bool v) {
    _prefs.setBool(_kMultiAudioMix, v);
    notifyListeners();
  }

  bool get mediaSessionEnabled => _prefs.getBool(_kMediaSession) ?? true;
  set mediaSessionEnabled(bool v) {
    _prefs.setBool(_kMediaSession, v);
    notifyListeners();
  }

  /// User-defined keybinds: action name -> list of accelerator strings.
  /// Accelerator format: `modifiers+key`, e.g. `Ctrl+S`, `Shift+Arrow Right`.
  Map<String, List<String>> get keybinds {
    final cached = _keybindsCache;
    if (cached != null) return cached;
    final raw = _prefs.getString(_kKeybinds);
    Map<String, List<String>> result;
    if (raw == null) {
      result = const {};
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          result = const {};
        } else {
          final out = <String, List<String>>{};
          decoded.forEach((k, v) {
            if (k is String && v is List) {
              out[k] = v.whereType<String>().toList(growable: false);
            }
          });
          result = Map<String, List<String>>.unmodifiable(out);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: keybinds decode failed: $e');
        }
        result = const {};
      }
    }
    _keybindsCache = result;
    return result;
  }

  set keybinds(Map<String, List<String>> value) {
    _keybindsCache = Map<String, List<String>>.unmodifiable(
      value.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))),
    );
    _prefs.setString(_kKeybinds, jsonEncode(value));
    notifyListeners();
  }

  void resetKeybinds() {
    _keybindsCache = const {};
    _prefs.remove(_kKeybinds);
    notifyListeners();
  }

  bool get resumePlaybackEnabled => _prefs.getBool(_kResumeEnabled) ?? true;
  set resumePlaybackEnabled(bool v) {
    _prefs.setBool(_kResumeEnabled, v);
    notifyListeners();
  }

  bool get playlistShuffle => _prefs.getBool(_kPlaylistShuffle) ?? false;
  set playlistShuffle(bool v) {
    _prefs.setBool(_kPlaylistShuffle, v);
    notifyListeners();
  }

  bool get allowMultipleInstances =>
      _prefs.getBool(_kAllowMultipleInstances) ?? false;
  set allowMultipleInstances(bool v) {
    _prefs.setBool(_kAllowMultipleInstances, v);
    unawaited(InstanceModeService.setAllowMultipleInstances(v));
    notifyListeners();
  }

  Future<void> syncInstanceModeFlag() async {
    await InstanceModeService.setAllowMultipleInstances(allowMultipleInstances);
  }

  Map<String, _ResumeEntry> _readResumePositions() {
    final cached = _resumePositionsCache;
    if (cached != null) {
      return Map<String, _ResumeEntry>.of(cached);
    }
    final raw = _prefs.getString(_kResumePositions);
    Map<String, _ResumeEntry> result;
    if (raw == null) {
      result = <String, _ResumeEntry>{};
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          result = <String, _ResumeEntry>{};
        } else {
          result = <String, _ResumeEntry>{};
          decoded.forEach((key, value) {
            if (key is String && value is Map) {
              final p = value['p'];
              final t = value['t'];
              if (p is int && p > 0 && t is int && t > 0) {
                result[key] = _ResumeEntry(positionMs: p, lastAccessMs: t);
              }
            }
          });
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dacx: resume positions decode failed: $e');
        }
        result = <String, _ResumeEntry>{};
      }
    }
    if (result.isNotEmpty) {
      final maxAccess = result.values
          .map((entry) => entry.lastAccessMs)
          .fold<int>(0, (max, value) => value > max ? value : max);
      if (maxAccess > _resumeAccessCounter) {
        _resumeAccessCounter = maxAccess;
      }
    }
    _resumePositionsCache = Map<String, _ResumeEntry>.of(result);
    return result;
  }

  /// Returns saved resume position in milliseconds, or null if none.
  int? resumePositionFor(String path) {
    if (!resumePlaybackEnabled) return null;
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    final positions = _readResumePositions();
    final entry = positions[normalized];
    if (entry == null) return null;
    // Touch the access timestamp so frequently-replayed files survive LRU
    // eviction even when many other files are saved between visits.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - entry.lastAccessMs > 1000) {
      final nextAccess = entry.lastAccessMs >= _resumeAccessCounter
          ? entry.lastAccessMs + 1
          : ++_resumeAccessCounter;
      _resumeAccessCounter = nextAccess;
      positions[normalized] = _ResumeEntry(
        positionMs: entry.positionMs,
        lastAccessMs: nextAccess,
      );
      _resumePositionsCache = Map<String, _ResumeEntry>.of(positions);
      _scheduleResumePersist();
    }
    return entry.positionMs;
  }

  void _scheduleResumePersist() {
    _resumePersistTimer?.cancel();
    _resumePersistTimer = Timer(_resumePersistDebounce, () {
      _resumePersistTimer = null;
      _persistResumePositionsToPrefs();
    });
  }

  void _persistResumePositionsToPrefs() {
    final positions = _resumePositionsCache ?? _readResumePositions();
    if (positions.isEmpty) {
      _prefs.remove(_kResumePositions);
      return;
    }
    _prefs.setString(_kResumePositions, _encodeResumePositions(positions));
  }

  /// Stores [positionMs] for [path]. Pass null/0 to clear.
  void saveResumePosition(String path, int? positionMs) {
    final normalized = path.trim();
    if (!_isSafeFilePath(normalized)) return;
    final positions = _readResumePositions();
    if (positionMs == null || positionMs <= 0) {
      if (positions.remove(normalized) == null) return;
    } else {
      final nextAccess = ++_resumeAccessCounter;
      positions[normalized] = _ResumeEntry(
        positionMs: positionMs,
        lastAccessMs: nextAccess,
      );
    }
    if (positions.length > maxResumeEntries) {
      // True LRU eviction: drop the entries whose lastAccessMs is oldest.
      final entries = positions.entries.toList()
        ..sort((a, b) => a.value.lastAccessMs.compareTo(b.value.lastAccessMs));
      final overflow = positions.length - maxResumeEntries;
      for (var i = 0; i < overflow; i++) {
        positions.remove(entries[i].key);
      }
    }
    _resumePositionsCache = Map<String, _ResumeEntry>.of(positions);
    _scheduleResumePersist();
  }

  String _encodeResumePositions(Map<String, _ResumeEntry> positions) {
    final out = <String, Map<String, int>>{};
    positions.forEach((k, v) {
      out[k] = {'p': v.positionMs, 't': v.lastAccessMs};
    });
    return jsonEncode(out);
  }

  void clearAllResumePositions() {
    _resumePersistTimer?.cancel();
    _resumePersistTimer = null;
    _resumePositionsCache = <String, _ResumeEntry>{};
    _prefs.remove(_kResumePositions);
    notifyListeners();
  }

  /// Clears all stored preferences and reverts to defaults.
  Future<void> resetAll() async {
    _resumePersistTimer?.cancel();
    _resumePersistTimer = null;
    _resumeAccessCounter = 0;
    _eqBandsCache = null;
    _keybindsCache = null;
    _resumePositionsCache = null;
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: recent files decode failed: $e');
      }
      return [];
    }
  }

  List<String> _readStoredRecentFiles() {
    final raw = _prefs.getString(_kRecentFiles);
    if (raw == null) return const [];
    return _decodeStoredRecentFiles(raw);
  }

  bool _recentFilePathExists(String path) {
    if (PlayableSource.isSupportedUrl(path)) {
      return PlayableSource.isDisplaySafeUrl(path);
    }
    try {
      return File(path).existsSync();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dacx: recent file exists check failed: $e');
      }
      return false;
    }
  }
}

class _ResumeEntry {
  final int positionMs;
  final int lastAccessMs;
  const _ResumeEntry({required this.positionMs, required this.lastAccessMs});
}
