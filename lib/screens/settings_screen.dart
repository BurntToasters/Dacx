import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../theme/window_visuals.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _s => widget.settings;
  bool _contentVisible = false;

  @override
  void initState() {
    super.initState();
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
                        _sectionHeader('Playback'),
                        _speedTile(),
                        _loopModeTile(),
                        SwitchListTile(
                          title: const Text('Auto-play on file open'),
                          value: _s.autoPlay,
                          onChanged: (v) => setState(() => _s.autoPlay = v),
                        ),
                        _hwDecTile(),
                        const Divider(),
                        _sectionHeader('Appearance'),
                        _themeModeTile(),
                        _accentColorTile(colorScheme),
                        _windowOpacityTile(),
                        if (Platform.isLinux) _linuxCompositorBlurTile(),
                        _windowBlurTile(),
                        _windowBlurStrengthTile(),
                        SwitchListTile(
                          title: const Text('Always on top'),
                          value: _s.alwaysOnTop,
                          onChanged: (v) => setState(() => _s.alwaysOnTop = v),
                        ),
                        SwitchListTile(
                          title: const Text('Remember window size & position'),
                          value: _s.rememberWindow,
                          onChanged: (v) =>
                              setState(() => _s.rememberWindow = v),
                        ),
                        const Divider(),
                        _sectionHeader('General'),
                        SwitchListTile(
                          title: const Text('Check for updates on launch'),
                          value: _s.updateCheckEnabled,
                          onChanged: (v) =>
                              setState(() => _s.updateCheckEnabled = v),
                        ),
                        _recentFilesTile(),
                        _checkForUpdatesTile(),
                        _keyboardShortcutsTile(),
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
                onPressed: () => Navigator.of(context).maybePop(),
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
          if (v != null) setState(() => _s.speed = v);
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
        onSelectionChanged: (s) => setState(() => _s.loopMode = s.first),
      ),
    );
  }

  Widget _hwDecTile() {
    return ListTile(
      title: const Text('Hardware acceleration'),
      subtitle: const Text('Requires restart to take effect'),
      trailing: DropdownButton<String>(
        value: _s.hwDec,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'auto', child: Text('Auto')),
          DropdownMenuItem(value: 'auto-safe', child: Text('Safe')),
          DropdownMenuItem(value: 'no', child: Text('Off')),
        ],
        onChanged: (v) {
          if (v != null) setState(() => _s.hwDec = v);
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
        onSelectionChanged: (s) => setState(() => _s.themeMode = s.first),
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
            onTap: () => setState(() => _s.accentColor = ac),
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
            onChanged: (v) => setState(() => _s.windowOpacity = v),
          ),
        ],
      ),
      trailing: Text('$percent%'),
    );
  }

  Widget _windowBlurTile() {
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux && _s.linuxCompositorBlurExperimental);
    if (!isSupported && _s.windowBlurEnabled) {
      _s.windowBlurEnabled = false;
    }

    return SwitchListTile(
      title: const Text('Background blur'),
      subtitle: Text(
        Platform.isLinux
            ? (_s.linuxCompositorBlurExperimental
                  ? 'Experimental: requires compositor support'
                  : 'Not available on Linux unless experimental mode is enabled')
            : 'Applies native blur behind app content',
      ),
      value: _s.windowBlurEnabled,
      onChanged: isSupported
          ? (v) => setState(() => _s.windowBlurEnabled = v)
          : null,
    );
  }

  Widget _windowBlurStrengthTile() {
    final isSupported =
        Platform.isWindows ||
        Platform.isMacOS ||
        (Platform.isLinux && _s.linuxCompositorBlurExperimental);
    final strength = _s.windowBlurStrength;
    final percent = (strength * 100).round();

    return ListTile(
      title: const Text('Glass strength'),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Platform.isWindows
                ? 'Adjusts blur material mode + translucency intensity'
                : 'Adjusts native glass material intensity',
          ),
          Slider(
            value: strength,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: '$percent%',
            onChanged: isSupported && _s.windowBlurEnabled
                ? (v) => setState(() => _s.windowBlurStrength = v)
                : null,
          ),
        ],
      ),
      trailing: Text('$percent%'),
    );
  }

  Widget _linuxCompositorBlurTile() {
    return SwitchListTile(
      title: const Text('Experimental Linux compositor blur'),
      subtitle: const Text(
        'Enables transparent window path for compositors that support blur (for example KDE blur rules)',
      ),
      value: _s.linuxCompositorBlurExperimental,
      onChanged: (v) => setState(() => _s.linuxCompositorBlurExperimental = v),
    );
  }

  Widget _recentFilesTile() {
    final count = _s.recentFiles.length;
    return ListTile(
      title: const Text('Recent files'),
      subtitle: Text('$count file${count == 1 ? '' : 's'}'),
      trailing: TextButton(
        onPressed: count > 0
            ? () => setState(() => _s.clearRecentFiles())
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
    setState(() => _checkingUpdate = true);
    try {
      final update = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (update != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dacx v${update.version} is available!'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => UpdateService().openReleasePage(update.url),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version.')),
        );
      }
    } catch (_) {
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
    return ListTile(
      title: const Text('Keyboard shortcuts'),
      leading: const Icon(Icons.keyboard),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keyboard Shortcuts'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ShortcutRow(openShortcut, 'Open File'),
                const _ShortcutRow('Space', 'Play / Pause'),
                const _ShortcutRow('←  →', 'Seek ±5 seconds'),
                const _ShortcutRow('↑  ↓', 'Volume ±5%'),
                const _ShortcutRow('M', 'Mute / Unmute'),
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

  Widget _resetTile() {
    return ListTile(
      title: const Text('Reset to defaults'),
      leading: const Icon(Icons.restore),
      onTap: () async {
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
          await _s.resetAll();
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings reset to defaults.')),
            );
          }
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
            applicationLegalese: '© 2026 run.rosie\nLicensed under GPLv3',
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
          title: const Text('About Dacx'),
          subtitle: Text('Version $version • GPLv3'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'View on GitHub',
            onPressed: () async {
              final uri = Uri.parse('https://github.com/BurntToasters/Dacx');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        );
      },
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
