import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/resume_playback_policy.dart';
import 'package:dacx/services/settings_service.dart';

void main() {
  group('ResumePlaybackPolicy.persistAction', () {
    test('skips when position is before min elapsed threshold', () {
      expect(
        ResumePlaybackPolicy.persistAction(
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 5),
        ),
        ResumePersistAction.skip,
      );
    });

    test('clears when position is within tail ignore window', () {
      expect(
        ResumePlaybackPolicy.persistAction(
          position: const Duration(minutes: 4, seconds: 50),
          duration: const Duration(minutes: 5),
          tailIgnoreSeconds: SettingsService.resumeTailIgnoreSeconds,
        ),
        ResumePersistAction.clear,
      );
    });

    test('saves when position is past min elapsed and outside tail window', () {
      expect(
        ResumePlaybackPolicy.persistAction(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 10),
        ),
        ResumePersistAction.save,
      );
    });

    test('saves when duration is unknown and position is past min elapsed', () {
      expect(
        ResumePlaybackPolicy.persistAction(
          position: const Duration(minutes: 1),
          duration: Duration.zero,
        ),
        ResumePersistAction.save,
      );
    });
  });

  group('ResumePlaybackPolicy.shouldClearNearEndResume', () {
    test('returns true when resume is within tail ignore window', () {
      expect(
        ResumePlaybackPolicy.shouldClearNearEndResume(
          resumeMs: 4 * 60 * 1000 + 50 * 1000,
          durationMs: 5 * 60 * 1000,
        ),
        isTrue,
      );
    });

    test('returns false when resume is safely before tail window', () {
      expect(
        ResumePlaybackPolicy.shouldClearNearEndResume(
          resumeMs: 2 * 60 * 1000,
          durationMs: 5 * 60 * 1000,
        ),
        isFalse,
      );
    });

    test('returns false when duration is unknown', () {
      expect(
        ResumePlaybackPolicy.shouldClearNearEndResume(
          resumeMs: 60 * 1000,
          durationMs: 0,
        ),
        isFalse,
      );
    });
  });

  group('ResumePlaybackPolicy.applyAction', () {
    test('skips when no resume is stored', () {
      expect(
        ResumePlaybackPolicy.applyAction(resumeMs: null, durationMs: 60_000),
        ResumeApplyAction.skip,
      );
      expect(
        ResumePlaybackPolicy.applyAction(resumeMs: 0, durationMs: 60_000),
        ResumeApplyAction.skip,
      );
    });

    test('waits when duration is still unknown', () {
      expect(
        ResumePlaybackPolicy.applyAction(resumeMs: 30_000, durationMs: 0),
        ResumeApplyAction.waitForDuration,
      );
    });

    test('clears stored resume near end of file', () {
      expect(
        ResumePlaybackPolicy.applyAction(
          resumeMs: 4 * 60 * 1000 + 50 * 1000,
          durationMs: 5 * 60 * 1000,
        ),
        ResumeApplyAction.clearStored,
      );
    });

    test('seeks when resume is valid', () {
      expect(
        ResumePlaybackPolicy.applyAction(
          resumeMs: 2 * 60 * 1000,
          durationMs: 5 * 60 * 1000,
        ),
        ResumeApplyAction.seek,
      );
    });
  });

  group('ResumePlaybackPolicy.formatHms', () {
    test('formats sub-hour durations as m:ss', () {
      expect(
        ResumePlaybackPolicy.formatHms(const Duration(minutes: 2, seconds: 5)),
        '2:05',
      );
    });

    test('formats hour-plus durations as h:mm:ss', () {
      expect(
        ResumePlaybackPolicy.formatHms(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
    });
  });
}
