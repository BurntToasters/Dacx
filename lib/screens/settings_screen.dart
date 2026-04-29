import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/debug_log_service.dart';
import '../services/hardware_acceleration_service.dart';
import '../services/settings_service.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final DebugLogService debugLog;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.debugLog,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _s => widget.settings;
  static final Uri _helpFaqUri = Uri.parse('https://help.rosie.run/dacx/en-us/faq');
  static final Uri _supportProjectUri = Uri.parse('https://rosie.run/support');
  late final UpdateService _updateService;
  bool _contentVisible = false;

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
    _updateService = UpdateService(
      debugLog: widget.debugLog,
      debugSource: 'settings_screen',
    );
    _log('settings_screen_init', category: DebugLogCategory.ui);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _contentVisible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visuals = context.windowVisuals;
    final isDesktopCustomChrome = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: isDesktopCustomChrome
          ? null
          : AppBar(title: const Text('Settings')),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [visuals.overlayColor, visuals.windowBottomColor],
          ),
        ),
        child: Column(
          children: [
            if (isDesktopCustomChrome) const CustomTitleBar(),
            if (isDesktopCustomChrome) _desktopHeader(context),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: visuals.overlayColor,
                  border: Border(top: BorderSide(color: visuals.dividerColor)),
                ),
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
                        const Divider(),
                        _sectionHeader('Playback'),
                        _speedTile(),
                        _loopModeTile(),
                        SwitchListTile(
                          title: const Text('Auto-play on file open'),
                          value: _s.autoPlay,
                          onChanged: (v) => setState(() {
                            _s.autoPlay = v;
                            _log(
                              'auto_play_changed',
                              detailsBuilder: () => {'value': v},
                            );
                          }),
                        ),
                        _hwDecTile(),
                        const Divider(),
                        _sectionHeader('Appearance'),
                        _themeModeTile(),
                        _accentColorTile(colorScheme),
                        if (_s.experimentalFeaturesEnabled) ...[
                          _experimentalTile(_windowOpacityTile()),
                          if (Platform.isLinux)
                            _experimentalTile(_linuxCompositorBlurTile()),
                          _experimentalTile(_windowBlurTile()),
                          _experimentalTile(_windowBlurStrengthTile()),
                        ],
                        SwitchListTile(
                          title: const Text('Always on top'),
                          value: _s.alwaysOnTop,
                          onChanged: (v) => setState(() {
                            _s.alwaysOnTop = v;
                            _log(
                              'always_on_top_changed',
                              detailsBuilder: () => {'value': v},
                            );
                          }),
                        ),
                        SwitchListTile(
                          title: const Text('Remember window size & position'),
                          value: _s.rememberWindow,
                          onChanged: (v) => setState(() {
                            _s.rememberWindow = v;
                            _log(
                              'remember_window_changed',
                              detailsBuilder: () => {'value': v},
                            );
                          }),
                        ),
                        const Divider(),
                        _sectionHeader('General'),
                        SwitchListTile(
                          title: const Text('Check for updates on launch'),
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
                        _recentFilesTile(),
                        _checkForUpdatesTile(),
                        _keyboardShortcutsTile(),
                        const Divider(),
                        _sectionHeader('Experimental'),
                        _experimentalTile(_experimentalFeaturesTile()),
                        if (_s.debugModeEnabled) ...[
                          const Divider(),
                          _sectionHeader('Debug'),
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
          ],
        ),
      ),
    );
  }

  Widget _desktopHeader(BuildContext context) {
    final visuals = context.windowVisuals;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: visuals.barColor,
        border: Border(bottom: BorderSide(color: visuals.dividerColor)),
      ),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () {
                  _log('settings_back_pressed', category: DebugLogCategory.ui);
                  Navigator.of(context).maybePop();
                },
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
    return ListTile(
      title: const Text('Playback speed'),
      trailing: DropdownButton<double>(
        value: _s.speed,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 0.5, child: Text('0.5×')),
          DropdownMenuItem(value: 0.75, child: Text('0.75×')),
          DropdownMenuItem(value: 1.0, child: Text('1.0×')),
          DropdownMenuItem(value: 1.25, child: Text('1.25×')),
          DropdownMenuItem(value: 1.5, child: Text('1.5×')),
          DropdownMenuItem(value: 2.0, child: Text('2.0×')),
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

  Widget _loopModeTile() {
    return ListTile(
      title: const Text('Loop mode'),
      trailing: SegmentedButton<LoopMode>(
        segments: LoopMode.values
            .map((m) => ButtonSegment(value: m, label: Text(m.label)))
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

  Widget _hwDecTile() {
    final hwAccelEnabled =
        HardwareAccelerationService.shouldEnableHardwareAcceleration(_s.hwDec);
    final hwReason = HardwareAccelerationService.debugStatusReason(_s.hwDec);

    return ListTile(
      title: const Text('Hardware acceleration'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Requires restart to take effect'),
          if (_s.debugModeEnabled) ...[
            const SizedBox(height: 4),
            Text(
              'Debug: HW acceleration active: ${hwAccelEnabled ? 'Yes' : 'No'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Debug: $hwReason',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      trailing: DropdownButton<String>(
        value: _s.hwDec,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'auto', child: Text('Auto')),
          DropdownMenuItem(value: 'auto-safe', child: Text('Safe')),
          DropdownMenuItem(value: 'no', child: Text('Off')),
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
    return ListTile(
      title: const Text('Theme'),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.system, label: Text('System')),
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
    return ListTile(
      title: const Text('Accent color'),
      trailing: Wrap(
        spacing: 6,
        children: AccentColor.values.map((ac) {
          final isSelected = ac == _s.accentColor;
          return GestureDetector(
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
          );
        }).toList(),
      ),
    );
  }

  Widget _windowOpacityTile() {
    final opacity = _s.windowOpacity;
    final percent = (opacity * 100).round();
    final windowsBlurMode = Platform.isWindows && _s.windowBlurEnabled;

    return ListTile(
      leading: _experimentalWarningIcon(),
      title: const Text('Window opacity'),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (windowsBlurMode)
            const Text('With blur on (Windows), this adjusts UI translucency.'),
          Slider(
            value: opacity,
            min: 0.65,
            max: 1.0,
            divisions: 14,
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
      trailing: Text('$percent%'),
    );
  }

  Widget _windowBlurTile() {
    if (!_s.experimentalFeaturesEnabled) {
      return const SizedBox.shrink();
    }
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux && _s.linuxCompositorBlurExperimental);
    final effectiveEnabled = isSupported && _s.windowBlurEnabled;

    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: const Text('Background blur'),
      subtitle: Text(
        Platform.isLinux
            ? (_s.linuxCompositorBlurExperimental
                  ? 'Experimental: requires compositor support'
                  : 'Not available on Linux unless experimental mode is enabled')
            : 'Applies native blur behind app content',
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
    if (!_s.experimentalFeaturesEnabled) {
      return const SizedBox.shrink();
    }
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux && _s.linuxCompositorBlurExperimental);
    final strength = _s.windowBlurStrength;
    final percent = (strength * 100).round();

    return ListTile(
      leading: _experimentalWarningIcon(),
      title: const Text('Glass strength'),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Platform.isWindows
                ? 'Adjusts native blur intensity'
                : 'Adjusts native glass material intensity',
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
      trailing: Text('$percent%'),
    );
  }

  Widget _linuxCompositorBlurTile() {
    if (!_s.experimentalFeaturesEnabled) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: const Text('Experimental Linux compositor blur'),
      subtitle: const Text(
        'Enables transparent window path for compositors that support blur (for example KDE blur rules)',
      ),
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

  Widget _experimentalFeaturesTile() {
    return SwitchListTile(
      secondary: _experimentalWarningIcon(),
      title: const Text('Enable Experimental Features'),
      subtitle: const Text('Experimental features are very unstable.'),
      value: _s.experimentalFeaturesEnabled,
      onChanged: (v) {
        setState(() {
          _s.experimentalFeaturesEnabled = v;
          _log(
            'experimental_features_changed',
            detailsBuilder: () => {'value': v},
          );
          if (!v) {
            _s.windowBlurEnabled = false;
            _s.windowOpacity = 1.0;
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
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: child,
      ),
    );
  }

  Widget _debugLogPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: ListenableBuilder(
            listenable: widget.debugLog,
            builder: (context, _) {
              final entries = widget.debugLog.entries;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Debug Log',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${widget.debugLog.entryCount} entries',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _copyDebugLog,
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Copy Log'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: widget.debugLog.entryCount > 0
                            ? _clearDebugLog
                            : null,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear Log'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No debug events yet.'),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[entries.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _renderDebugEntry(entry),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    height: 1.28,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _renderDebugEntry(DebugLogEntry entry) {
    final detailsText = _renderDebugDetails(entry.details);
    final base =
        '[${entry.timestamp.toIso8601String()}] '
        '[${entry.severity.name.toUpperCase()}] '
        '[${entry.category.name}] '
        '${entry.event}';
    final msg = entry.message?.trim();
    if (msg != null && msg.isNotEmpty && detailsText.isNotEmpty) {
      return '$base - $msg | $detailsText';
    }
    if (msg != null && msg.isNotEmpty) return '$base - $msg';
    if (detailsText.isNotEmpty) return '$base | $detailsText';
    return base;
  }

  String _renderDebugDetails(Map<String, Object?> details) {
    if (details.isEmpty) return '';
    final keys = details.keys.toList()..sort();
    return keys
        .map((key) {
          final safe = details[key]?.toString().replaceAll('\n', r'\n');
          return '$key=$safe';
        })
        .join(', ');
  }

  Future<void> _copyDebugLog() async {
    final text = widget.debugLog.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    _log(
      'debug_log_copied',
      category: DebugLogCategory.ui,
      detailsBuilder: () => {'entry_count': widget.debugLog.entryCount},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Debug log copied to clipboard.')),
    );
  }

  void _clearDebugLog() {
    widget.debugLog.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug log cleared.')));
  }

  Widget _recentFilesTile() {
    final count = _s.recentFiles.length;
    return ListTile(
      title: const Text('Recent files'),
      subtitle: Text('$count file${count == 1 ? '' : 's'}'),
      trailing: TextButton(
        onPressed: count > 0
            ? () => setState(() {
                _s.clearRecentFiles();
                _log('recent_files_cleared');
              })
            : null,
        child: const Text('Clear'),
      ),
    );
  }

  bool _checkingUpdate = false;

  Widget _checkForUpdatesTile() {
    return ListTile(
      title: const Text('Check for updates'),
      trailing: _checkingUpdate
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonal(
              onPressed: _doCheckForUpdate,
              child: const Text('Check now'),
            ),
    );
  }

  Future<void> _doCheckForUpdate() async {
    _log('manual_update_check_requested', category: DebugLogCategory.update);
    setState(() => _checkingUpdate = true);
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (!_updateService.lastCheckSucceeded) {
        _log(
          'manual_update_check_failed',
          category: DebugLogCategory.update,
          severity: DebugSeverity.warn,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for updates.')),
        );
        return;
      }
      if (update != null) {
        _log(
          'manual_update_available',
          category: DebugLogCategory.update,
          detailsBuilder: () => {'version': update.version},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dacx v${update.version} is available!'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _updateService.openReleasePage(update.url),
            ),
          ),
        );
      } else {
        _log('manual_update_not_available', category: DebugLogCategory.update);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version.')),
        );
      }
    } catch (e) {
      _log(
        'manual_update_check_failed',
        category: DebugLogCategory.update,
        message: e.toString(),
        severity: DebugSeverity.error,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check for updates.')),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _keyboardShortcutsTile() {
    final openShortcut = Platform.isMacOS ? '⌘O' : 'Ctrl+O';
    final reopenShortcut = Platform.isMacOS ? '⌘R' : 'Ctrl+R';
    return ListTile(
      title: const Text('Keyboard shortcuts'),
      leading: const Icon(Icons.keyboard),
      onTap: () {
        _log('keyboard_shortcuts_opened', category: DebugLogCategory.ui);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keyboard Shortcuts'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ShortcutRow(openShortcut, 'Open File'),
                _ShortcutRow(reopenShortcut, 'Reopen Last'),
                const _ShortcutRow('Space', 'Play / Pause'),
                const _ShortcutRow('←  →', 'Seek ±5 seconds'),
                const _ShortcutRow('↑  ↓', 'Volume ±5%'),
                const _ShortcutRow('M', 'Mute / Unmute'),
                const _ShortcutRow('F', 'Toggle Fullscreen'),
                const _ShortcutRow('Esc', 'Exit Fullscreen'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _helpFaqTile() {
    return ListTile(
      title: const Text('Help'),
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
    return ListTile(
      title: const Text('Support this project'),
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
    return ListTile(
      title: const Text('Reset to defaults'),
      leading: const Icon(Icons.restore),
      onTap: () async {
        _log('reset_settings_prompt_opened');
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reset Settings'),
            content: const Text(
              'This will reset all settings to their default values. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reset'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          _log('reset_settings_confirmed');
          await _s.resetAll();
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings reset to defaults.')),
            );
          }
        } else {
          _log('reset_settings_cancelled');
        }
      },
    );
  }

  Widget _licensesTile() {
    return ListTile(
      title: const Text('Open source licenses'),
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
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        return ListTile(
          title: GestureDetector(
            onTap: _promptToggleDebugMode,
            behavior: HitTestBehavior.opaque,
            child: const Text('About Dacx'),
          ),
          subtitle: Text('Version $version • GPLv3'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'View on GitHub',
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
    final currentlyEnabled = _s.debugModeEnabled;
    final actionLabel = currentlyEnabled ? 'Disable' : 'Enable';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionLabel Debug Mode?'),
        content: Text(
          currentlyEnabled
              ? 'Do you want to disable hidden debug mode?'
              : 'Do you want to enable hidden debug mode? (Debug mode uses more system resources and may cause performance degradation while enabled)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
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
          _s.debugModeEnabled ? 'Debug mode enabled.' : 'Debug mode disabled.',
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String shortcut;
  final String description;

  const _ShortcutRow(this.shortcut, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              shortcut,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }
}
