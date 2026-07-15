import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/playback_mix_policy.dart';
import 'package:dacx/playback/player_controller.dart';

Tracks _tracks({
  List<AudioTrack> audio = const [],
  List<VideoTrack> video = const [],
}) {
  return Tracks(audio: audio, video: video, subtitle: const []);
}

void main() {
  group('PlayerController.onPosition', () {
    test('skips updates while seeking', () {
      final player = PlayerController()..isSeeking = true;
      expect(
        player.onPosition(const Duration(seconds: 5)),
        PositionUiUpdate.skip,
      );
      expect(player.position, Duration.zero);
    });

    test('notifies when second boundary changes', () {
      final player = PlayerController()
        ..position = const Duration(milliseconds: 900);
      expect(
        player.onPosition(const Duration(milliseconds: 1100)),
        PositionUiUpdate.notify,
      );
    });

    test('silently updates sub-threshold ticks within same second', () {
      final player = PlayerController()
        ..position = const Duration(milliseconds: 1000);
      expect(
        player.onPosition(const Duration(milliseconds: 1150)),
        PositionUiUpdate.silent,
      );
      expect(player.position, const Duration(milliseconds: 1150));
    });

    test('notifies when delta exceeds threshold within same second', () {
      final player = PlayerController()
        ..position = const Duration(milliseconds: 1000);
      expect(
        player.onPosition(const Duration(milliseconds: 1250)),
        PositionUiUpdate.notify,
      );
    });
  });

  group('PlayerController.inferAudioOnlyFromTracks', () {
    test('returns null when no real audio tracks exist', () {
      expect(
        PlayerController.inferAudioOnlyFromTracks(
          _tracks(
            audio: [AudioTrack.auto()],
            video: const [VideoTrack('v1', 'video', null)],
          ),
        ),
        isNull,
      );
    });

    test('returns true for audio plus album-art video only', () {
      expect(
        PlayerController.inferAudioOnlyFromTracks(
          _tracks(
            audio: const [AudioTrack('a1', 'eng', null)],
            video: const [VideoTrack('art', 'Album art', null, albumart: true)],
          ),
        ),
        isTrue,
      );
    });

    test('returns false when a non-art video track exists', () {
      expect(
        PlayerController.inferAudioOnlyFromTracks(
          _tracks(
            audio: const [AudioTrack('a1', 'eng', null)],
            video: const [VideoTrack('v1', 'Main', null)],
          ),
        ),
        isFalse,
      );
    });
  });

  group('PlayerController.firstEmbeddedAlbumArtTrack', () {
    test('skips auto and no tracks', () {
      expect(
        PlayerController.firstEmbeddedAlbumArtTrack(
          _tracks(
            video: [
              VideoTrack.auto(),
              VideoTrack.no(),
              VideoTrack('art', 'cover', null, image: true),
            ],
          ),
        )?.id,
        'art',
      );
    });
  });

  group('PlayerController.beginSourceLoad', () {
    test('resets transport and track state for new source', () {
      final player = PlayerController()
        ..currentSource = PlayableSource.file('/old.mp4')
        ..position = const Duration(seconds: 30)
        ..duration = const Duration(minutes: 5)
        ..currentTracks = _tracks(audio: const [AudioTrack('a', 'x', null)])
        ..chapters = const []
        ..resumePathInProgress = '/old.mp4'
        ..lastAppliedAfChain = 'chain';

      final begin = player.beginSourceLoad(
        PlayableSource.file('/new.mp3'),
        'mp3',
      );

      expect(begin.isAudioByExtension, isTrue);
      expect(player.currentSource?.value, '/new.mp3');
      expect(player.position, Duration.zero);
      expect(player.duration, Duration.zero);
      expect(player.currentTracks, isNull);
      expect(player.chapters, isEmpty);
      expect(player.resumePathInProgress, isNull);
      expect(player.lastAppliedAfChain, isNull);
      expect(player.hasVideoOutput, isFalse);
    });
  });

  group('PlayerController.clearSourceOnLoadFailure', () {
    test('clears source and audio flags', () {
      final player = PlayerController()
        ..currentSource = PlayableSource.file('/x.mp4')
        ..isAudioFile = true
        ..albumArtTrackId = 'art'
        ..resumePathInProgress = '/x.mp4';

      player.clearSourceOnLoadFailure();

      expect(player.currentSource, isNull);
      expect(player.isAudioFile, isFalse);
      expect(player.albumArtTrackId, isNull);
      expect(player.resumePathInProgress, isNull);
    });
  });

  group('PlayerController.cacheTracksForLoad', () {
    test('updates audio-only inference and mix eligibility', () {
      final player = PlayerController();
      final mixState = PlaybackMixLoadState();
      final result = player.cacheTracksForLoad(
        _tracks(
          audio: const [
            AudioTrack('1', 'eng', null),
            AudioTrack('2', 'jpn', null),
          ],
          video: const [VideoTrack('v1', 'Main', null)],
        ),
        mixLoadState: mixState,
        multiAudioMixEnabled: true,
      );

      expect(result.audioOnlyChanged, isFalse);
      expect(result.inferredAudioOnly, isFalse);
      expect(result.shouldRefreshMix, isTrue);
      expect(mixState.canMix, isTrue);
    });
  });

  group('PlayerController formatting helpers', () {
    test('formatDuration renders h:mm:ss or mm:ss', () {
      expect(
        PlayerController.formatDuration(const Duration(hours: 1, minutes: 2)),
        '1:02:00',
      );
      expect(
        PlayerController.formatDuration(const Duration(minutes: 3, seconds: 4)),
        '03:04',
      );
    });

    test('osdTitle uses basename for files and displayName for streams', () {
      final player = PlayerController()
        ..currentSource = PlayableSource.file('/music/song.flac');
      expect(player.osdTitle(), 'song');

      player.currentSource = PlayableSource.url('https://x/live');
      expect(player.osdTitle(), 'live');
    });

    test('stripOsdTimestamp removes hidden suffix', () {
      expect(
        PlayerController.stripOsdTimestamp('Paused\u2009·\u20091234'),
        'Paused',
      );
      expect(PlayerController.stripOsdTimestamp('Plain'), 'Plain');
    });
  });

  group('PlayerController.onVideoWidth', () {
    test('returns true only when output presence changes', () {
      final player = PlayerController();
      expect(player.onVideoWidth(1280), isTrue);
      expect(player.hasVideoOutput, isTrue);
      expect(player.onVideoWidth(1920), isFalse);
      expect(player.onVideoWidth(null), isTrue);
      expect(player.hasVideoOutput, isFalse);
    });
  });

  group('PlayerController.clampSeekTarget', () {
    test('returns null when duration is unknown', () {
      expect(
        PlayerController.clampSeekTarget(
          position: const Duration(seconds: 10),
          offset: const Duration(seconds: 5),
          duration: Duration.zero,
        ),
        isNull,
      );
    });

    test('clamps relative seek within duration bounds', () {
      expect(
        PlayerController.clampSeekTarget(
          position: const Duration(seconds: 10),
          offset: const Duration(seconds: 5),
          duration: const Duration(seconds: 20),
        ),
        const Duration(seconds: 15),
      );
      expect(
        PlayerController.clampSeekTarget(
          position: const Duration(seconds: 2),
          offset: const Duration(seconds: -10),
          duration: const Duration(seconds: 20),
        ),
        Duration.zero,
      );
      expect(
        PlayerController.clampSeekTarget(
          position: const Duration(seconds: 18),
          offset: const Duration(seconds: 10),
          duration: const Duration(seconds: 20),
        ),
        const Duration(seconds: 20),
      );
    });
  });

  group('PlayerController.clearMediaSurface', () {
    test('clears loaded media flags and transport', () {
      final player = PlayerController()
        ..currentSource = PlayableSource.file('/song.mp3')
        ..isAudioFile = true
        ..hasVideoOutput = true
        ..hasAlbumArtTrack = true
        ..albumArtTrackId = 'art'
        ..position = const Duration(seconds: 30)
        ..duration = const Duration(minutes: 3);

      player.clearMediaSurface();

      expect(player.currentSource, isNull);
      expect(player.isAudioFile, isFalse);
      expect(player.hasVideoOutput, isFalse);
      expect(player.hasAlbumArtTrack, isFalse);
      expect(player.albumArtTrackId, isNull);
      expect(player.position, Duration.zero);
      expect(player.duration, Duration.zero);
    });
  });
}
