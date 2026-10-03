import 'dart:async';

import 'package:flutter/material.dart';

import '../playback/advanced_playback_models.dart';
import '../services/advanced_playback_controller.dart';
import '../services/settings_service.dart';

class AdvancedPlaybackDialog extends StatefulWidget {
  const AdvancedPlaybackDialog({
    super.key,
    required this.controller,
    required this.settings,
  });

  final AdvancedPlaybackController controller;
  final SettingsService settings;

  @override
  State<AdvancedPlaybackDialog> createState() => _AdvancedPlaybackDialogState();
}

class _AdvancedPlaybackDialogState extends State<AdvancedPlaybackDialog> {
  AdvancedPlaybackController get _controller => widget.controller;
  SettingsService get _settings => widget.settings;
  String? _textColorError;
  String? _outlineColorError;

  String _delayLabel(int milliseconds) {
    if (milliseconds == 0) return '0 ms';
    return milliseconds > 0 ? '+$milliseconds ms' : '$milliseconds ms';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _settings]),
      builder: (context, _) {
        final adjustment = _controller.adjustment;
        final markers = _controller.markers;
        return AlertDialog(
          key: const ValueKey('advanced-playback-dialog'),
          title: const Text('Advanced playback'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Optional tools for repeat, synchronization, bookmarks, and subtitle appearance.',
                  ),
                  const SizedBox(height: 16),
                  _loopSection(context),
                  const Divider(height: 28),
                  _delaySection(
                    context,
                    label: 'Audio delay',
                    value: adjustment.audioMs,
                    onBack: () => _controller.adjustAudioDelay(-100),
                    onForward: () => _controller.adjustAudioDelay(100),
                    onReset: _controller.resetAudioDelay,
                    minusKey: 'advanced-audio-minus',
                    plusKey: 'advanced-audio-plus',
                    resetKey: 'advanced-audio-reset',
                  ),
                  _delaySection(
                    context,
                    label: 'Subtitle delay',
                    value: adjustment.subtitleMs,
                    onBack: () => _controller.adjustSubtitleDelay(-100),
                    onForward: () => _controller.adjustSubtitleDelay(100),
                    onReset: _controller.resetSubtitleDelay,
                    minusKey: 'advanced-subtitle-minus',
                    plusKey: 'advanced-subtitle-plus',
                    resetKey: 'advanced-subtitle-reset',
                  ),
                  if (_controller.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _controller.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const Divider(height: 28),
                  _markersSection(context, markers),
                  const Divider(height: 28),
                  _subtitleSection(context),
                  const Divider(height: 28),
                  SwitchListTile.adaptive(
                    key: const ValueKey('advanced-disable'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Advanced playback tools'),
                    subtitle: const Text(
                      'Turn off to restore the minimalist player. Saved choices stay stored.',
                    ),
                    value: _settings.advancedPlaybackToolsEnabled,
                    onChanged: (value) async {
                      await _controller.setEnabled(value);
                      if (!value && context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _loopSection(BuildContext context) {
    final stage = _controller.loopStage;
    final label = switch (stage) {
      AdvancedLoopStage.clear => 'Set A',
      AdvancedLoopStage.aSet => 'Set B',
      AdvancedLoopStage.active => 'Clear A-B',
    };
    final key = switch (stage) {
      AdvancedLoopStage.clear => 'advanced-set-a',
      AdvancedLoopStage.aSet => 'advanced-set-b',
      AdvancedLoopStage.active => 'advanced-clear-loop',
    };
    final range = stage == AdvancedLoopStage.active
        ? '${_format(_controller.a!)} – ${_format(_controller.b!)}'
        : switch (stage) {
            AdvancedLoopStage.clear => 'No A-B range set',
            AdvancedLoopStage.aSet => 'A: ${_format(_controller.a!)}',
            AdvancedLoopStage.active => '',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'A-B repeat',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(range),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: ValueKey(key),
          onPressed: () => _controller.cycleLoop(),
          child: Text(label),
        ),
      ],
    );
  }

  Widget _delaySection(
    BuildContext context, {
    required String label,
    required int value,
    required Future<void> Function() onBack,
    required Future<void> Function() onForward,
    required Future<void> Function() onReset,
    required String minusKey,
    required String plusKey,
    required String resetKey,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: ValueKey(minusKey),
          tooltip: 'Decrease $label',
          onPressed: value <= -SettingsService.playbackDelayLimitMs
              ? null
              : () => onBack(),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 76, child: Center(child: Text(_delayLabel(value)))),
        IconButton(
          key: ValueKey(plusKey),
          tooltip: 'Increase $label',
          onPressed: value >= SettingsService.playbackDelayLimitMs
              ? null
              : () => onForward(),
          icon: const Icon(Icons.add_circle_outline),
        ),
        IconButton(
          key: ValueKey(resetKey),
          tooltip: 'Reset $label',
          onPressed: value == 0 ? null : () => onReset(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _markersSection(BuildContext context, List<PlaybackMarker> markers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Playback markers',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text('Markers are saved per file or safe URL.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('advanced-add-marker'),
          onPressed: _controller.source == null
              ? null
              : () => _controller.addMarker(),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Add at current time'),
        ),
        if (markers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No markers yet.'),
          )
        else
          ...markers.map(
            (marker) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.bookmark_outline),
              title: Text(marker.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                _format(Duration(milliseconds: marker.positionMs)),
              ),
              onTap: () => _controller.seekMarker(marker),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Rename marker',
                    onPressed: () => _renameMarker(context, marker),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete marker',
                    onPressed: () => _controller.deleteMarker(marker.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _subtitleSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Subtitle appearance',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Applies to plain text subtitles. Authored ASS styling is preserved; bitmap subtitles cannot be restyled.',
        ),
        _sliderRow(
          label: 'Font size',
          value: _settings.subtitleFontSize.toDouble(),
          min: 24,
          max: 72,
          divisions: 48,
          text: '${_settings.subtitleFontSize}',
          onChanged: (v) {
            _settings.subtitleFontSize = v.round();
            _controller.applySubtitleAppearance();
          },
        ),
        _sliderRow(
          label: 'Vertical position',
          value: _settings.subtitlePosition.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          text: '${_settings.subtitlePosition}%',
          onChanged: (v) {
            _settings.subtitlePosition = v.round();
            _controller.applySubtitleAppearance();
          },
        ),
        _sliderRow(
          label: 'Outline size',
          value: _settings.subtitleOutlineSize,
          min: 0,
          max: 4,
          divisions: 16,
          text: _settings.subtitleOutlineSize.toStringAsFixed(2),
          onChanged: (v) {
            _settings.subtitleOutlineSize = v;
            _controller.applySubtitleAppearance();
          },
        ),
        TextFormField(
          key: const ValueKey('advanced-subtitle-text-color'),
          initialValue: _settings.subtitleTextColor,
          decoration: InputDecoration(
            labelText: 'Text color (hex)',
            hintText: '#FFFFFFFF',
            errorText: _textColorError,
          ),
          onFieldSubmitted: (value) {
            _submitColor(value, outline: false);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _colorPreset(
              key: 'advanced-text-color-white',
              label: 'White',
              value: '#FFFFFFFF',
              outline: false,
            ),
            _colorPreset(
              key: 'advanced-text-color-yellow',
              label: 'Yellow',
              value: '#FFFF00FF',
              outline: false,
            ),
          ],
        ),
        TextFormField(
          key: const ValueKey('advanced-subtitle-outline-color'),
          initialValue: _settings.subtitleOutlineColor,
          decoration: InputDecoration(
            labelText: 'Outline color (hex)',
            hintText: '#000000FF',
            errorText: _outlineColorError,
          ),
          onFieldSubmitted: (value) {
            _submitColor(value, outline: true);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _colorPreset(
              key: 'advanced-outline-color-black',
              label: 'Black',
              value: '#000000FF',
              outline: true,
            ),
            _colorPreset(
              key: 'advanced-outline-color-white',
              label: 'White',
              value: '#FFFFFFFF',
              outline: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorPreset({
    required String key,
    required String label,
    required String value,
    required bool outline,
  }) {
    return OutlinedButton(
      key: ValueKey(key),
      onPressed: () => _submitColor(value, outline: outline),
      child: Text(label),
    );
  }

  void _submitColor(String value, {required bool outline}) {
    final valid = SettingsService.isValidSubtitleColor(value);
    setState(() {
      if (outline) {
        _outlineColorError = valid ? null : 'Enter a 6- or 8-digit hex color.';
      } else {
        _textColorError = valid ? null : 'Enter a 6- or 8-digit hex color.';
      }
    });
    if (!valid) return;
    if (outline) {
      _settings.subtitleOutlineColor = value;
    } else {
      _settings.subtitleTextColor = value;
    }
    unawaited(_controller.applySubtitleAppearance());
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String text,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: text,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 52, child: Text(text, textAlign: TextAlign.end)),
      ],
    );
  }

  Future<void> _renameMarker(
    BuildContext context,
    PlaybackMarker marker,
  ) async {
    final text = TextEditingController(text: marker.label);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename marker'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    if (next != null) _controller.renameMarker(marker.id, next);
  }

  static String _format(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
