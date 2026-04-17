import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _s => widget.settings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
          SwitchListTile(
            title: const Text('Always on top'),
            value: _s.alwaysOnTop,
            onChanged: (v) => setState(() => _s.alwaysOnTop = v),
          ),
          SwitchListTile(
            title: const Text('Remember window size & position'),
            value: _s.rememberWindow,
            onChanged: (v) => setState(() => _s.rememberWindow = v),
          ),
          const Divider(),
          _sectionHeader('General'),
          SwitchListTile(
            title: const Text('Check for updates on launch'),
            value: _s.updateCheckEnabled,
            onChanged: (v) => setState(() => _s.updateCheckEnabled = v),
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
            content: Text('DACX v${update.version} is available!'),
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
    return ListTile(
      title: const Text('Keyboard shortcuts'),
      leading: const Icon(Icons.keyboard),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keyboard Shortcuts'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ShortcutRow('Space', 'Play / Pause'),
                _ShortcutRow('←  →', 'Seek ±5 seconds'),
                _ShortcutRow('↑  ↓', 'Volume ±5%'),
                _ShortcutRow('M', 'Mute / Unmute'),
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
      onTap: () {
        showLicensePage(
          context: context,
          applicationName: 'DACX',
          applicationLegalese: '© 2026 run.rosie\nLicensed under GPLv3',
        );
      },
    );
  }

  Widget _aboutTile() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        return ListTile(
          title: const Text('About DACX'),
          subtitle: Text('Version $version • GPLv3'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'View on GitHub',
            onPressed: () async {
              final uri = Uri.parse('https://github.com/BurntToasters/DACX');
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }
}
