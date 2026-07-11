import 'dart:async';

import '../playback/audio_filter_chain.dart';
import '../services/audio_spectrum_service.dart';
import '../services/player_service.dart';
import '../services/settings_service.dart';
import 'player_controller.dart';

/// Coordinates EQ + spectrum filter apply and spectrum start/stop sync.
///
/// Extracted from [PlayerScreen] so filter lifecycle stays testable without
/// the full widget tree.
class PlayerAudioSession {
  PlayerAudioSession({
    required IPlayerService playerService,
    required SettingsService settings,
    required PlayerController player,
    required AudioSpectrumService spectrum,
  }) : _playerService = playerService,
       _settings = settings,
       _player = player,
       _spectrum = spectrum;

  final IPlayerService _playerService;
  final SettingsService _settings;
  final PlayerController _player;
  final AudioSpectrumService _spectrum;

  AudioSpectrumService get spectrum => _spectrum;

  /// Whether spectrum analysis should be in the af chain right now.
  bool get spectrumWanted =>
      _settings.audioWaveformEnabled &&
      _player.isAudioFile &&
      _spectrum.isActive &&
      !_settings.multiAudioMix;

  Future<AudioFilterApplyResult> applyMergedAudioFilters() async {
    if (spectrumWanted || _spectrum.isActive) {
      _spectrum.markFilterDirty();
    }
    final result = await AudioFilterChain.apply(
      lastAppliedChain: _player.lastAppliedAfChain,
      eqEnabled: _settings.eqEnabled,
      eqBands: _settings.eqBands,
      spectrumWanted: spectrumWanted,
      spectrumCurrentlyConfirmed: _spectrum.isFilterInstalled,
      setAudioFilter: _playerService.setAudioFilter,
    );
    if (!result.skipped) {
      _player.lastAppliedAfChain = result.appliedChain;
    }
    if (result.spectrumInstalled || result.needsSpectrumConfirm) {
      _spectrum.confirmFilterInstalled();
    } else if (result.spectrumFailed) {
      _spectrum.confirmFilterFailed();
    }
    return result;
  }

  void syncSpectrum(bool playing) {
    final action = SpectrumSyncPolicy.resolve(
      playing: playing,
      isAudioFile: _player.isAudioFile,
      audioWaveformEnabled: _settings.audioWaveformEnabled,
      spectrumCurrentlyActive: _spectrum.isActive,
      multiAudioMixEnabled: _settings.multiAudioMix,
    );
    switch (action) {
      case SpectrumSyncAction.startAndApply:
        unawaited(_spectrum.start().then((_) => applyMergedAudioFilters()));
      case SpectrumSyncAction.stopAndApply:
        unawaited(_spectrum.stop().then((_) => applyMergedAudioFilters()));
      case SpectrumSyncAction.applyOnly:
        unawaited(applyMergedAudioFilters());
    }
  }

  Future<void> disableSpectrumDueToCapabilityFailure() async {
    if (!_spectrum.capabilityFailed) return;
    if (_settings.audioWaveformEnabled) {
      _settings.audioWaveformEnabled = false;
    }
    await _spectrum.stop();
    await applyMergedAudioFilters();
  }
}
