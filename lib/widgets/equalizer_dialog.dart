import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/equalizer_service.dart';
import '../services/settings_service.dart';
import 'dialog_sizing.dart';

Future<void> showEqualizerDialog({
  required BuildContext context,
  required SettingsService settings,
  required Future<void> Function() onApply,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx);
          final bands = List<double>.from(settings.eqBands);
          return AlertDialog(
            title: Text(l10n.dialogEqualizerTitle),
            content: SizedBox(
              width: dialogWidth(ctx, 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(l10n.dialogEqualizerEnable),
                      const Spacer(),
                      Switch(
                        value: settings.eqEnabled,
                        onChanged: (v) {
                          settings.eqEnabled = v;
                          unawaited(onApply());
                          setLocal(() {});
                        },
                      ),
                    ],
                  ),
                  DropdownButton<String>(
                    value: settings.eqPreset,
                    isExpanded: true,
                    onChanged: (id) {
                      if (id == null) return;
                      final preset = EqualizerService.presetById(id);
                      if (preset == null) return;
                      settings.eqPreset = id;
                      settings.eqBands = preset.gains;
                      unawaited(onApply());
                      setLocal(() {});
                    },
                    items: kEqPresets
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(eqPresetLabel(l10n, p.id)),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: math.min(
                      220.0,
                      math.max(120.0, dialogHeight(ctx, 360) - 140),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(SettingsService.eqBandCount, (i) {
                        final freq = SettingsService.eqBandFrequencies[i];
                        final label = freq < 1000
                            ? '$freq'
                            : '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k';
                        return Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    min: -12,
                                    max: 12,
                                    divisions: 48,
                                    value: bands[i],
                                    onChanged: (v) {
                                      bands[i] = v;
                                      settings.eqBands = bands;
                                      settings.eqPreset = 'custom';
                                      unawaited(onApply());
                                      setLocal(() {});
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                label,
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                              Text(
                                '${bands[i].toStringAsFixed(0)}dB',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  settings.eqBands = List<double>.filled(
                    SettingsService.eqBandCount,
                    0,
                  );
                  settings.eqPreset = 'flat';
                  unawaited(onApply());
                  setLocal(() {});
                },
                child: Text(l10n.actionReset),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.actionClose),
              ),
            ],
          );
        },
      );
    },
  );
}

String eqPresetLabel(AppLocalizations l10n, String id) {
  return switch (id) {
    'flat' => l10n.eqPresetFlat,
    'bass_boost' => l10n.eqPresetBassBoost,
    'bass_reduce' => l10n.eqPresetBassReduce,
    'treble_boost' => l10n.eqPresetTrebleBoost,
    'vocal' => l10n.eqPresetVocal,
    'rock' => l10n.eqPresetRock,
    'electronic' => l10n.eqPresetElectronic,
    'acoustic' => l10n.eqPresetAcoustic,
    'loudness' => l10n.eqPresetLoudness,
    'classical' => l10n.eqPresetClassical,
    _ => id,
  };
}
