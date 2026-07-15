import '../playback/audio_filter_chain.dart';
import '../services/player_service.dart';
import '../services/settings_service.dart';
import 'player_controller.dart';

/// Coordinates EQ filter apply for the player session.
///
/// Extracted from [PlayerScreen] so filter lifecycle stays testable without
/// the full widget tree.
class PlayerAudioSession {
  PlayerAudioSession({
    required IPlayerService playerService,
    required SettingsService settings,
    required PlayerController player,
  }) : _playerService = playerService,
       _settings = settings,
       _player = player;

  final IPlayerService _playerService;
  final SettingsService _settings;
  final PlayerController _player;

  Future<AudioFilterApplyResult> applyMergedAudioFilters() async {
    final result = await AudioFilterChain.apply(
      lastAppliedChain: _player.lastAppliedAfChain,
      eqEnabled: _settings.eqEnabled,
      eqBands: _settings.eqBands,
      setAudioFilter: _playerService.setAudioFilter,
    );
    if (!result.skipped) {
      _player.lastAppliedAfChain = result.appliedChain;
    }
    return result;
  }
}
