import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../playback/playback_speed_policy.dart';
import '../services/debug_log_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/settings_service.dart';
import '../theme/glass_decorations.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_log_panel.dart';
import '../widgets/manual_update_check.dart';
import '../widgets/update_progress_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;
  final UpdateService updateService;
  final VoidCallback? onEditKeybinds;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.debugLog,
    required this.updateService,
    this.onEditKeybinds,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _s => widget.settings;
  static final Uri _helpFaqUri = Uri.parse(
    'https://help.rosie.run/dacx/en-us/faq',
  );
  static final Uri _supportProjectUri = Uri.parse('https://rosie.run/support');
  UpdateService get _updateService => widget.updateService;
  bool _contentVisible = false;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _log(
    String event, {
    DebugLogCategory category = DebugLogCategory.settings,
    String? message,
    Map<String, Object?> details = const {},
    String? Function()? messageBuilder,
    Map<String, Object?> Function()? detailsBuilder,
    DebugSeverity severity = DebugSeverity.info,
  }) {
    if (!widget.debugLog.isEnabled) return;
    widget.debugLog.logLazy(
      category: category,
      event: event,
      messageBuilder:
          messageBuilder ?? (message == null ? null : () => message),
      detailsBuilder:
          detailsBuilder ?? (details.isEmpty ? null : () => details),
      severity: severity,
    );
  }

  @override
  void initState() {
    super.initState();
    _log('settings_screen_init', category: DebugLogCategory.ui);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      setState(() => _contentVisible = true);
    });
  }

  void _popSettings() {
    _log('settings_back_pressed', category: DebugLogCategory.ui);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visuals = context.windowVisuals;
    final isDesktopCustomChrome = Platform.isMacOS || Platform.isWindows;
    final l10n = AppLocalizations.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _popSettings,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: isDesktopCustomChrome
              ? null
              : AppBar(title: Text(l10n.settingsTitle)),
          body: GlassOverlayBackground(
            child: Column(
              children: [
                if (isDesktopCustomChrome) const CustomTitleBar(),
                if (isDesktopCustomChrome) _desktopHeader(context),
                Expanded(
                  child: DecoratedBox(
                    decoration: visuals.overlayDecoration(),
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 210),
                        curve: Curves.easeOutCubic,
                        opacity: _contentVisible ? 1 : 0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          offset: _contentVisible
                              ? Offset.zero
                              : const Offset(0, 0.02),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              _helpFaqTile(),
                              _supportProjectTile(),
                              if (Platform.isLinux &&
                                  (Platform.environment['FLATPAK_ID'] ?? '')
                                      .isNotEmpty)
                                ListTile(
                                  leading: const Icon(Icons.info_outline),
                                  title: Text(l10n.flatpakSandboxHint),
                                  dense: true,
                                ),
                              const Divider(),
                              _sectionHeader(l10n.settingsSectionPlayback),
                              _speedTile(),
                              _loopModeTile(),
                              SwitchListTile(
                                title: Text(l10n.settingsAutoPlay),
                                value: _s.autoPlay,
                                onChanged: (v) => setState(() {
                                  _s.autoPlay = v;
                                  _log(
                                    'auto_play_changed',
                                    detailsBuilder: () => {'value': v},
                                  );
                                }),
                              ),
                              SwitchListTile(
                                title: Text(l10n.settingsResumePlayback),
                                subtitle: Text(l10n.settingsResumeSubtitle),
                                value: _s.resumePlaybackEnabled,
                                onChanged: (v) => setState(
                                  () => _s.resumePlaybackEnabled = v,
                                ),
                              ),
                              SwitchListTile(
                                title: Text(l10n.settingsOnScreenDisplay),
                                subtitle: Text(l10n.settingsOsdSubtitle),
                                value: _s.osdEnabled,
                                onChanged: (v) =>
                                    setState(() => _s.osdEnabled = v),
                              ),
                              _screenshotDirTile(),
                              _screenshotFormatTile(),
                              SwitchListTile(
                                title: Text(l10n.settingsSeekPreview),
                                subtitle: Text(
                                  l10n.settingsSeekPreviewSubtitle,
                                ),
                                value: _s.seekPreviewEnabled,
                                onChanged: (v) =>
                                    setState(() => _s.seekPreviewEnabled = v),
                              ),
                              SwitchListTile(
                                title: Text(l10n.settingsMediaSession),
                                subtitle: Text(
                                  l10n.settingsMediaSessionSubtitle,
                                ),
                                value: _s.mediaSessionEnabled,
                                onChanged: (v) =>
                                    setState(() => _s.mediaSessionEnabled = v),
                              ),
                              _hwDecTile(),
                              const Divider(),
                              _sectionHeader(l10n.settingsSectionAppearance),
                              _themeModeTile(),
                              _accentColorTile(colorScheme),
                              if (Platform.isWindows || Platform.isMacOS) ...[
                                _windowOpacityTile(),
                                _windowBlurTile(),
                                _windowBlurStrengthTile(),
                              ],
                              SwitchListTile(
                                title: Text(l10n.settingsAlwaysOnTop),
                                value: _s.alwaysOnTop,
                                onChanged: (v) => setState(() {
                                  _s.alwaysOnTop = v;
                                  _log(
                                    'always_on_top_changed',
                                    detailsBuilder: () => {'value': v},
                                  );
                                }),
                              ),
                              if (Platform.isWindows ||
                                  Platform.isMacOS ||
                                  Platform.isLinux)
                                SwitchListTile(
                                  title: Text(l10n.settingsMinimizeToTray),
                                  subtitle: Text(
                                    l10n.settingsMinimizeToTraySubtitle,
                                  ),
                                  value: _s.minimizeToTray,
                                  onChanged: (v) => setState(() {
                                    _s.minimizeToTray = v;
                                    _log(
                                      'minimize_to_tray_changed',
                                      detailsBuilder: () => {'value': v},
                                    );
                                  }),
                                ),
                              SwitchListTile(
                                title: Text(l10n.settingsRememberWindow),
                                value: _s.rememberWindow,
                                onChanged: (v) => setState(() {
                                  _s.rememberWindow = v;
                                  _log(
                                    'remember_window_changed',
                                    detailsBuilder: () => {'value': v},
                                  );
                                }),
                              ),
                              SwitchListTile(
                                title: Text(l10n.settingsAllowMultipleWindows),
                                subtitle: Text(
                                  l10n.settingsAllowMultipleWindowsSubtitle,
                                ),
                                value: _s.allowMultipleInstances,
                                onChanged: (v) => setState(() {
                                  _s.allowMultipleInstances = v;
                                  _log(
                                    'allow_multiple_instances_changed',
                                    detailsBuilder: () => {'value': v},
                                  );
                                }),
                              ),
                              const Divider(),
                              _sectionHeader(l10n.settingsSectionGeneral),
                              SwitchListTile(
                                title: Text(
                                  l10n.settingsCheckForUpdatesOnLaunch,
                                ),
                                value: _s.updateCheckEnabled,
                                onChanged: (v) => setState(() {
                                  _s.updateCheckEnabled = v;
                                  _log(
                                    'update_check_on_launch_changed',
                                    category: DebugLogCategory.update,
                                    detailsBuilder: () => {'value': v},
                                  );
                                }),
                              ),
                              _updateChannelTile(),
                              _recentFilesTile(),
                              _checkForUpdatesTile(),
                              _keyboardShortcutsTile(),
                              const Divider(),
                              _sectionHeader(l10n.settingsSectionExperimental),
                              _experimentalTile(_experimentalFeaturesTile()),
                              if (_s.experimentalFeaturesEnabled) ...[
                                if (Platform.isLinux) ...[
                                  _experimentalTile(_linuxCompositorBlurTile()),
                                  _experimentalTile(_windowOpacityTile()),
                                  _experimentalTile(_windowBlurTile()),
                                  _experimentalTile(_windowBlurStrengthTile()),
                                ],
                                _experimentalTile(_audioWaveformTile()),
                                _experimentalTile(_multiAudioMixTile()),
                              ],
                              if (_s.debugModeEnabled) ...[
                                const Divider(),
                                _sectionHeader(l10n.settingsSectionDebug),
                                _debugLogPanel(),
                              ],
                              const Divider(),
                              _resetTile(),
                              const Divider(),
                              _licensesTile(),
                              _aboutTile(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GlassChrome(
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.settingsBack,
                onPressed: _popSettings,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    l10n.settingsTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _speedTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsPlaybackSpeed),
      trailing: DropdownButton<double>(
        value: PlaybackSpeedPolicy.nearestPreset(_s.speed),
        underline: const SizedBox.shrink(),
        items: [
          for (final rate in PlaybackSpeedPolicy.presets)
            DropdownMenuItem(
              value: rate,
              child: Text(PlaybackSpeedPolicy.formatLabel(rate)),
            ),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _s.speed = v);
            _log(
              'playback_speed_changed',
              detailsBuilder: () => {'value': v.toStringAsFixed(2)},
            );
          }
        },
      ),
    );
  }

  String _loopModeLabel(AppLocalizations l10n, LoopMode mode) {
    return switch (mode) {
      LoopMode.none => l10n.settingsLoopOff,
      LoopMode.single => l10n.settingsLoopSingle,
      LoopMode.loop => l10n.settingsLoopAll,
    };
  }

  String _accentColorName(AppLocalizations l10n, AccentColor ac) {
    return switch (ac) {
      AccentColor.blueGrey => l10n.accentColorBlueGrey,
      AccentColor.blue => l10n.accentColorBlue,
      AccentColor.teal => l10n.accentColorTeal,
      AccentColor.purple => l10n.accentColorPurple,
      AccentColor.red => l10n.accentColorRed,
      AccentColor.orange => l10n.accentColorOrange,
      AccentColor.green => l10n.accentColorGreen,
      AccentColor.pink => l10n.accentColorPink,
    };
  }

  Widget _loopModeTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsLoopMode),
      trailing: SegmentedButton<LoopMode>(
        segments: LoopMode.values
            .map(
              (m) =>
                  ButtonSegment(value: m, label: Text(_loopModeLabel(l10n, m))),
            )
            .toList(),
        selected: {_s.loopMode},
        onSelectionChanged: (s) => setState(() {
          _s.loopMode = s.first;
          _log(
            'loop_mode_changed',
            detailsBuilder: () => {'value': s.first.name},
          );
        }),
      ),
    );
  }

  Widget _screenshotDirTile() {
    final l10n = AppLocalizations.of(context);
    final dir = _s.screenshotDir;
    return ListTile(
      title: Text(l10n.settingsScreenshotDir),
      subtitle: Text(
        dir ?? l10n.settingsScreenshotDirSubtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final picked = await FilePicker.getDirectoryPath(
                dialogTitle: l10n.settingsChooseScreenshotDir,
              );
              if (picked == null || !mounted) return;
              setState(() {
                _s.screenshotDir = picked;
                _log(
                  'screenshot_dir_changed',
                  detailsBuilder: () => {'value': picked},
                );
              });
            },
            child: Text(l10n.settingsChooseScreenshotDir),
          ),
          TextButton(
            onPressed: dir == null
                ? null
                : () => setState(() {
                    _s.screenshotDir = null;
                    _log('screenshot_dir_reset');
                  }),
            child: Text(l10n.settingsResetScreenshotDir),
          ),
        ],
      ),
    );
  }

  Widget _screenshotFormatTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsScreenshotFormat),
      trailing: SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'png',
            label: Text(l10n.settingsScreenshotFormatPng),
          ),
          ButtonSegment(
            value: 'jpg',
            label: Text(l10n.settingsScreenshotFormatJpg),
          ),
        ],
        selected: {_s.screenshotFormat},
        onSelectionChanged: (s) => setState(() {
          _s.screenshotFormat = s.first;
          _log(
            'screenshot_format_changed',
            detailsBuilder: () => {'value': s.first},
          );
        }),
      ),
    );
  }

  Widget _hwDecTile() {
    final l10n = AppLocalizations.of(context);
    final hwAccelEnabled =
        HardwareAccelerationService.shouldEnableHardwareAcceleration(_s.hwDec);
    final hwReason = HardwareAccelerationService.debugStatusReason(_s.hwDec);

    return ListTile(
      title: Text(l10n.settingsHardwareAcceleration),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.settingsHardwareAccelerationRestartNote),
          if (_s.debugModeEnabled) ...[
            const SizedBox(height: 4),
            Text(
              l10n.settingsHwAccelDebugActive(
                hwAccelEnabled ? l10n.hwAccelStateYes : l10n.hwAccelStateNo,
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              l10n.settingsHwAccelDebugReason(hwReason),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      trailing: DropdownButton<String>(
        value: _s.hwDec,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(value: 'auto', child: Text(l10n.settingsHwDecAuto)),
          DropdownMenuItem(
            value: 'auto-safe',
            child: Text(l10n.settingsHwDecSafe),
          ),
          DropdownMenuItem(value: 'no', child: Text(l10n.settingsHwDecOff)),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _s.hwDec = v);
            _log(
              'hardware_acceleration_mode_changed',
              category: DebugLogCategory.hwaccel,
              detailsBuilder: () => {
                'value': v,
                'active':
                    HardwareAccelerationService.shouldEnableHardwareAcceleration(
                      v,
                    ),
                'reason': HardwareAccelerationService.debugStatusReason(v),
              },
            );
          }
        },
      ),
    );
  }

  Widget _themeModeTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsTheme),
      trailing: SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text(l10n.settingsThemeDark),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            label: Text(l10n.settingsThemeLight),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            label: Text(l10n.settingsThemeSystem),
          ),
        ],
        selected: {_s.themeMode},
        onSelectionChanged: (s) => setState(() {
          _s.themeMode = s.first;
          _log(
            'theme_mode_changed',
            detailsBuilder: () => {'value': s.first.name},
          );
        }),
      ),
    );
  }

  Widget _accentColorTile(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsAccentColor),
      trailing: Wrap(
        spacing: 6,
        children: AccentColor.values.map((ac) {
          final isSelected = ac == _s.accentColor;
          return Semantics(
            label: l10n.semanticsAccentColor(_accentColorName(l10n, ac)),
            button: true,
            selected: isSelected,
            child: GestureDetector(
              onTap: () => setState(() {
                _s.accentColor = ac;
                _log(
                  'accent_color_changed',
                  detailsBuilder: () => {'value': ac.name},
                );
              }),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: ac.color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: colorScheme.onSurface, width: 2.5)
                      : null,
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16, color: colorScheme.onSurface)
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _windowOpacityTile() {
    final l10n = AppLocalizations.of(context);
    final opacity = _s.windowOpacity.clamp(
      SettingsService.windowOpacityMin,
      1.0,
    );
    final percent = (opacity * 100).round();
    final windowsBlurMode =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        _s.windowBlurEnabled;
    const minOpacity = SettingsService.windowOpacityMin;
    final divisions = ((1.0 - minOpacity) / 0.05).round();

    return ListTile(
      title: Text(l10n.settingsWindowOpacity),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (windowsBlurMode) Text(l10n.settingsWindowOpacityBlurNote),
          Slider(
            value: opacity,
            min: minOpacity,
            max: 1.0,
            divisions: divisions,
            label: '$percent%',
            onChanged: (v) => setState(() {
              _s.windowOpacity = v;
              _log(
                'window_opacity_changed',
                detailsBuilder: () => {'value': v.toStringAsFixed(3)},
              );
            }),
          ),
        ],
      ),
      trailing: Text(l10n.settingsPercent(percent)),
    );
  }

  Widget _windowBlurTile() {
    final l10n = AppLocalizations.of(context);
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux &&
            _s.experimentalFeaturesEnabled &&
            _s.linuxCompositorBlurExperimental);
    final effectiveEnabled = isSupported && _s.windowBlurEnabled;

    return SwitchListTile(
      title: Text(l10n.settingsBackgroundBlur),
      subtitle: Text(
        Platform.isLinux
            ? (_s.linuxCompositorBlurExperimental
                  ? l10n.settingsBlurLinuxExperimentalOn
                  : l10n.settingsBlurLinuxExperimentalOff)
            : l10n.settingsBlurNativeSubtitle,
      ),
      value: effectiveEnabled,
      onChanged: isSupported
          ? (v) => setState(() {
              _s.windowBlurEnabled = v;
              _log('window_blur_changed', detailsBuilder: () => {'value': v});
            })
          : null,
    );
  }

  Widget _windowBlurStrengthTile() {
    final l10n = AppLocalizations.of(context);
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux &&
            _s.experimentalFeaturesEnabled &&
            _s.linuxCompositorBlurExperimental);
    final strength = _s.windowBlurStrength;
    final percent = (strength * 100).round();

    return ListTile(
      title: Text(l10n.settingsGlassStrength),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Platform.isWindows
                ? l10n.settingsBlurIntensityWindows
                : l10n.settingsBlurIntensityMac,
          ),
          Slider(
            value: strength,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: '$percent%',
            onChanged: isSupported && _s.windowBlurEnabled
                ? (v) => setState(() {
                    _s.windowBlurStrength = v;
                    _log(
                      'window_blur_strength_changed',
                      detailsBuilder: () => {'value': v.toStringAsFixed(3)},
                    );
                  })
                : null,
          ),
        ],
      ),
      trailing: Text(l10n.settingsPercent(percent)),
    );
  }

  Widget _linuxCompositorBlurTile() {
    final l10n = AppLocalizations.of(context);
    if (!_s.experimentalFeaturesEnabled) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: Text(l10n.settingsLinuxCompositorBlur),
      subtitle: Text(l10n.settingsLinuxCompositorBlurSubtitle),
      value: _s.linuxCompositorBlurExperimental,
      onChanged: (v) => setState(() {
        _s.linuxCompositorBlurExperimental = v;
        _log(
          'linux_compositor_blur_changed',
          detailsBuilder: () => {'value': v},
        );
      }),
    );
  }

  Widget _audioWaveformTile() {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: Text(l10n.settingsAudioWaveform),
      subtitle: Text(l10n.settingsAudioWaveformSubtitle),
      value: _s.audioWaveformEnabled,
      onChanged: (v) => setState(() {
        _s.audioWaveformEnabled = v;
        _log('audio_waveform_changed', detailsBuilder: () => {'value': v});
      }),
    );
  }

  Widget _multiAudioMixTile() {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: Text(l10n.menuMixAllAudioTracks),
      subtitle: Text(l10n.settingsMultiAudioMixSubtitle),
      value: _s.multiAudioMix,
      onChanged: (v) => setState(() {
        _s.multiAudioMix = v;
        if (v) {
          _s.audioWaveformEnabled = false;
        }
        _log('multi_audio_mix_changed', detailsBuilder: () => {'value': v});
      }),
    );
  }

  Widget _experimentalFeaturesTile() {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: Text(l10n.settingsExperimentalEnable),
      subtitle: Text(
        '${l10n.settingsExperimentalUnstable}\n${l10n.settingsExperimentalStoredPrefsHint}',
      ),
      isThreeLine: true,
      value: _s.experimentalFeaturesEnabled,
      onChanged: (v) {
        setState(() {
          _s.experimentalFeaturesEnabled = v;
          _log(
            'experimental_features_changed',
            detailsBuilder: () => {'value': v},
          );
          // Win/mac blur + opacity live under Appearance (graduated). Only
          // clear them on Linux, where they remain experimental-gated.
          if (!v && Platform.isLinux) {
            _s.windowBlurEnabled = false;
            _s.windowOpacity = 1.0;
            _s.linuxCompositorBlurExperimental = false;
          }
        });
      },
    );
  }

  ({Color background, Color border, Color icon}) _experimentalColors(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = Color.lerp(scheme.tertiary, Colors.amber, 0.72)!;
    final background = Color.alphaBlend(
      amber.withValues(alpha: isDark ? 0.16 : 0.11),
      scheme.surface,
    );
    final border = amber.withValues(alpha: isDark ? 0.45 : 0.36);
    final icon = Color.lerp(
      amber,
      isDark ? Colors.amber.shade200 : Colors.amber.shade700,
      0.22,
    )!;
    return (background: background, border: border, icon: icon);
  }

  Widget _experimentalWarningIcon() {
    final colors = _experimentalColors(context);
    return Icon(Icons.warning_amber_rounded, color: colors.icon);
  }

  Widget _experimentalTile(Widget child) {
    final colors = _experimentalColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Material(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget _debugLogPanel() => DebugLogPanel(debugLog: widget.debugLog);

  Widget _recentFilesTile() {
    final l10n = AppLocalizations.of(context);
    final count = _s.recentFiles.length;
    return ListTile(
      title: Text(l10n.settingsRecentFiles),
      subtitle: Text(l10n.settingsRecentFilesCount(count)),
      trailing: TextButton(
        onPressed: count > 0
            ? () => setState(() {
                _s.clearRecentFiles();
                _log('recent_files_cleared');
              })
            : null,
        child: Text(l10n.actionClear),
      ),
    );
  }

  bool _checkingUpdate = false;

  Widget _updateChannelTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsUpdateChannel),
      subtitle: Text(l10n.settingsUpdateChannelSubtitle),
      trailing: SegmentedButton<UpdateChannel>(
        segments: [
          ButtonSegment(
            value: UpdateChannel.auto,
            label: Text(l10n.settingsUpdateChannelAuto),
          ),
          ButtonSegment(
            value: UpdateChannel.stable,
            label: Text(l10n.settingsUpdateChannelStable),
          ),
          ButtonSegment(
            value: UpdateChannel.beta,
            label: Text(l10n.settingsUpdateChannelBeta),
          ),
        ],
        selected: {_s.updateChannel},
        onSelectionChanged: (s) => setState(() {
          _s.updateChannel = s.first;
          _s.lastUpdateCheck = 0;
          _log(
            'update_channel_changed',
            category: DebugLogCategory.update,
            detailsBuilder: () => {'value': s.first.name},
          );
        }),
      ),
    );
  }

  Widget _checkForUpdatesTile() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(l10n.settingsCheckForUpdates),
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _doCheckForUpdate,
                  child: Text(l10n.settingsCheckNow),
                ),
        ),
        if (Platform.isLinux)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${l10n.settingsLinuxUpdateHint} ${linuxUpdateGuidance(l10n)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.64),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _doCheckForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      await runManualUpdateCheck(
        context: context,
        updateService: _updateService,
        settings: _s,
        debugLog: widget.debugLog,
        onLog: (event, {message, severity}) {
          _log(
            event,
            category: DebugLogCategory.update,
            message: message,
            severity: severity ?? DebugSeverity.info,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _keyboardShortcutsTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsKeyboardShortcuts),
      leading: const Icon(Icons.keyboard),
      subtitle: Text(l10n.keybindsTip),
      onTap: () {
        _log('keyboard_shortcuts_opened', category: DebugLogCategory.ui);
        final edit = widget.onEditKeybinds;
        if (edit != null) {
          edit();
          return;
        }
        // Fallback if opened without a host (tests): show tip only.
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final dialogL10n = AppLocalizations.of(dialogContext);
            return AlertDialog(
              title: Text(dialogL10n.settingsKeyboardShortcuts),
              content: Text(dialogL10n.keybindsTip),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dialogL10n.actionClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _helpFaqTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsHelp),
      leading: const Icon(Icons.help_outline),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _openExternalLink(
        uri: _helpFaqUri,
        requestedEvent: 'open_faq_requested',
        launchedEvent: 'open_faq_launched',
        failedEvent: 'open_faq_failed',
      ),
    );
  }

  Widget _supportProjectTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsSupportProject),
      leading: const Icon(Icons.favorite_border),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _openExternalLink(
        uri: _supportProjectUri,
        requestedEvent: 'open_support_requested',
        launchedEvent: 'open_support_launched',
        failedEvent: 'open_support_failed',
      ),
    );
  }

  Future<void> _openExternalLink({
    required Uri uri,
    required String requestedEvent,
    required String launchedEvent,
    required String failedEvent,
  }) async {
    _log(
      requestedEvent,
      category: DebugLogCategory.ui,
      detailsBuilder: () => {'url': uri.toString()},
    );

    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          _log(
            launchedEvent,
            category: DebugLogCategory.ui,
            detailsBuilder: () => {'url': uri.toString()},
          );
        } else {
          _log(
            failedEvent,
            category: DebugLogCategory.ui,
            severity: DebugSeverity.warn,
            detailsBuilder: () => {'url': uri.toString()},
          );
        }
        return;
      }
    } catch (e) {
      _log(
        failedEvent,
        category: DebugLogCategory.ui,
        severity: DebugSeverity.warn,
        message: e.toString(),
        detailsBuilder: () => {'url': uri.toString()},
      );
      return;
    }

    _log(
      failedEvent,
      category: DebugLogCategory.ui,
      severity: DebugSeverity.warn,
      detailsBuilder: () => {'url': uri.toString()},
    );
  }

  Widget _resetTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsResetDefaults),
      leading: const Icon(Icons.restore),
      onTap: () async {
        _log('reset_settings_prompt_opened');
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final dialogL10n = AppLocalizations.of(dialogContext);
            return AlertDialog(
              title: Text(dialogL10n.settingsResetTitle),
              content: Text(dialogL10n.settingsResetConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(dialogL10n.actionCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(dialogL10n.actionReset),
                ),
              ],
            );
          },
        );
        if (confirm == true) {
          _log('reset_settings_confirmed');
          await _s.resetAll();
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.snackSettingsReset)));
          }
        } else {
          _log('reset_settings_cancelled');
        }
      },
    );
  }

  Widget _licensesTile() {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsOpenSourceLicenses),
      leading: const Icon(Icons.description_outlined),
      onTap: _openLicenses,
    );
  }

  void _openLicenses() {
    _log('licenses_opened', category: DebugLogCategory.ui);
    final base = Theme.of(context);
    final colorScheme = base.colorScheme;
    final opaqueSurface = colorScheme.surface;

    final licenseTheme = base.copyWith(
      scaffoldBackgroundColor: opaqueSurface,
      canvasColor: opaqueSurface,
      cardColor: opaqueSurface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: opaqueSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: Platform.isMacOS ? 144 : base.appBarTheme.leadingWidth,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          fixedSize: Platform.isMacOS ? const Size(120, 48) : null,
          alignment: Platform.isMacOS
              ? Alignment.centerRight
              : Alignment.center,
          padding: Platform.isMacOS ? EdgeInsets.zero : null,
          shape: Platform.isMacOS
              ? const _OffsetCircleBorder(72.0)
              : const CircleBorder(),
        ),
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: licenseTheme,
          child: const LicensePage(
            applicationName: 'Dacx',
            applicationLegalese: 'Made With ❤️ By: BurntToasters/Rosie.run',
          ),
        ),
      ),
    );
  }

  Widget _aboutTile() {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: UpdateService.currentVersionFromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data ?? '...';
        return ListTile(
          title: GestureDetector(
            onTap: _promptToggleDebugMode,
            behavior: HitTestBehavior.opaque,
            child: Text(l10n.settingsAboutDacx),
          ),
          subtitle: Text(l10n.settingsAboutVersion(version)),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: l10n.settingsViewOnGitHub,
            onPressed: () async {
              final uri = Uri.parse('https://github.com/BurntToasters/Dacx');
              _log(
                'open_github_requested',
                category: DebugLogCategory.ui,
                detailsBuilder: () => {'url': uri.toString()},
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                _log(
                  'open_github_launched',
                  category: DebugLogCategory.ui,
                  detailsBuilder: () => {'url': uri.toString()},
                );
              } else {
                _log(
                  'open_github_failed',
                  category: DebugLogCategory.ui,
                  severity: DebugSeverity.warn,
                  detailsBuilder: () => {'url': uri.toString()},
                );
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _promptToggleDebugMode() async {
    final l10n = AppLocalizations.of(context);
    final currentlyEnabled = _s.debugModeEnabled;
    final actionLabel = currentlyEnabled
        ? l10n.settingsActionDisable
        : l10n.settingsActionEnable;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dialogL10n.settingsDebugModeTitle(actionLabel)),
          content: Text(
            currentlyEnabled
                ? dialogL10n.settingsDebugModeDisablePrompt
                : dialogL10n.settingsDebugModeEnablePrompt,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogL10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      _log('debug_mode_toggle_cancelled', category: DebugLogCategory.system);
      return;
    }
    if (currentlyEnabled) {
      _log(
        'debug_mode_toggled',
        category: DebugLogCategory.system,
        detailsBuilder: () => {'enabled': false},
      );
    }
    setState(() => _s.debugModeEnabled = !currentlyEnabled);
    if (_s.debugModeEnabled) {
      _log(
        'debug_mode_toggled',
        category: DebugLogCategory.system,
        detailsBuilder: () => {'enabled': true},
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _s.debugModeEnabled
              ? l10n.snackDebugModeEnabled
              : l10n.snackDebugModeDisabled,
        ),
      ),
    );
  }
}

class _OffsetCircleBorder extends CircleBorder {
  final double offset;
  const _OffsetCircleBorder(this.offset, {super.side});

  Rect _shift(Rect rect) {
    return Rect.fromLTWH(
      rect.left + offset,
      rect.top,
      rect.height,
      rect.height,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return super.getInnerPath(_shift(rect), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return super.getOuterPath(_shift(rect), textDirection: textDirection);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, _shift(rect), textDirection: textDirection);
  }

  @override
  _OffsetCircleBorder copyWith({BorderSide? side, double? eccentricity}) {
    return _OffsetCircleBorder(offset, side: side ?? this.side);
  }
}
