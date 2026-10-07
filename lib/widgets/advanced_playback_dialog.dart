import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
        final l10n = AppLocalizations.of(context);
        final adjustment = _controller.adjustment;
        final error = _controller.error;
        final markers = _controller.markers;
        return AlertDialog(
          key: const ValueKey('advanced-playback-dialog'),
          title: Text(l10n.advancedDialogTitle),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.advancedDialogIntro),
                  const SizedBox(height: 16),
                  _loopSection(context),
                  const Divider(height: 28),
                  _delaySection(
                    context,
                    label: l10n.advancedAudioDelay,
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
                    label: l10n.advancedSubtitleDelay,
                    value: adjustment.subtitleMs,
                    onBack: () => _controller.adjustSubtitleDelay(-100),
                    onForward: () => _controller.adjustSubtitleDelay(100),
                    onReset: _controller.resetSubtitleDelay,
                    minusKey: 'advanced-subtitle-minus',
                    plusKey: 'advanced-subtitle-plus',
                    resetKey: 'advanced-subtitle-reset',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _errorText(l10n, error),
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
                    title: Text(l10n.settingsAdvancedPlaybackTools),
                    subtitle: Text(l10n.advancedToolsToggleHint),
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
              child: Text(l10n.actionClose),
            ),
          ],
        );
      },
    );
  }

  Widget _loopSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = _controller.loopStage;
    final label = switch (stage) {
      AdvancedLoopStage.clear => l10n.advancedLoopSetA,
      AdvancedLoopStage.aSet => l10n.advancedLoopSetB,
      AdvancedLoopStage.active => l10n.advancedLoopClear,
    };
    final key = switch (stage) {
      AdvancedLoopStage.clear => 'advanced-set-a',
      AdvancedLoopStage.aSet => 'advanced-set-b',
      AdvancedLoopStage.active => 'advanced-clear-loop',
    };
    final range = stage == AdvancedLoopStage.active
        ? '${_format(_controller.a!)} – ${_format(_controller.b!)}'
        : switch (stage) {
            AdvancedLoopStage.clear => l10n.advancedLoopNone,
            AdvancedLoopStage.aSet => l10n.advancedLoopPointA(
              _format(_controller.a!),
            ),
            AdvancedLoopStage.active => '',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.advancedLoopTitle, style: _headingStyle),
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
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: ValueKey(minusKey),
          tooltip: l10n.advancedDelayDecrease(label),
          onPressed: value <= -SettingsService.playbackDelayLimitMs
              ? null
              : () => onBack(),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 76, child: Center(child: Text(_delayLabel(value)))),
        IconButton(
          key: ValueKey(plusKey),
          tooltip: l10n.advancedDelayIncrease(label),
          onPressed: value >= SettingsService.playbackDelayLimitMs
              ? null
              : () => onForward(),
          icon: const Icon(Icons.add_circle_outline),
        ),
        IconButton(
          key: ValueKey(resetKey),
          tooltip: l10n.advancedDelayReset(label),
          onPressed: value == 0 ? null : () => onReset(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _markersSection(BuildContext context, List<PlaybackMarker> markers) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.advancedMarkersTitle, style: _headingStyle),
        const SizedBox(height: 4),
        Text(l10n.advancedMarkersHint),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('advanced-add-marker'),
          onPressed: _controller.source == null
              ? null
              : () => _controller.addMarker(),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.advancedMarkerAdd),
        ),
        if (markers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.advancedMarkersEmpty),
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
                    tooltip: l10n.advancedMarkerRename,
                    onPressed: () => _renameMarker(context, marker),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: l10n.advancedMarkerDelete,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.advancedSubtitleTitle, style: _headingStyle),
        const SizedBox(height: 4),
        Text(l10n.advancedSubtitleHint),
        _sliderRow(
          label: l10n.advancedSubtitleFontSize,
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
          label: l10n.advancedSubtitlePosition,
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
          label: l10n.advancedSubtitleOutlineSize,
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
            labelText: l10n.advancedSubtitleTextColor,
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
              label: l10n.advancedColorWhite,
              value: '#FFFFFFFF',
              outline: false,
            ),
            _colorPreset(
              key: 'advanced-text-color-yellow',
              label: l10n.advancedColorYellow,
              value: '#FFFF00FF',
              outline: false,
            ),
          ],
        ),
        TextFormField(
          key: const ValueKey('advanced-subtitle-outline-color'),
          initialValue: _settings.subtitleOutlineColor,
          decoration: InputDecoration(
            labelText: l10n.advancedSubtitleOutlineColor,
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
              label: l10n.advancedColorBlack,
              value: '#000000FF',
              outline: true,
            ),
            _colorPreset(
              key: 'advanced-outline-color-white',
              label: l10n.advancedColorWhite,
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
    final message = valid
        ? null
        : AppLocalizations.of(context).advancedColorInvalid;
    setState(() {
      if (outline) {
        _outlineColorError = message;
      } else {
        _textColorError = message;
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
        title: Text(AppLocalizations.of(ctx).advancedMarkerRename),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, text.text),
            child: Text(AppLocalizations.of(ctx).actionSave),
          ),
        ],
      ),
    );
    text.dispose();
    if (next != null) _controller.renameMarker(marker.id, next);
  }

  static const _headingStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 16,
  );

  static String _errorText(AppLocalizations l10n, AdvancedPlaybackError error) {
    return switch (error) {
      AdvancedPlaybackError.applySync => l10n.advancedErrorApplySync,
      AdvancedPlaybackError.applySubtitleAppearance =>
        l10n.advancedErrorApplySubtitleAppearance,
      AdvancedPlaybackError.applyAudioDelay =>
        l10n.advancedErrorApplyAudioDelay,
      AdvancedPlaybackError.applySubtitleDelay =>
        l10n.advancedErrorApplySubtitleDelay,
      AdvancedPlaybackError.resetAudioDelay =>
        l10n.advancedErrorResetAudioDelay,
      AdvancedPlaybackError.resetSubtitleDelay =>
        l10n.advancedErrorResetSubtitleDelay,
      AdvancedPlaybackError.applyLoop => l10n.advancedErrorApplyLoop,
      AdvancedPlaybackError.clearLoop => l10n.advancedErrorClearLoop,
    };
  }

  static String _format(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
