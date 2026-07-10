import 'dart:async';

import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/audio_spectrum_service.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/audio_spectrum_visualizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('visualizer coverage smoke', () {
    test('audio spectrum filter segment is labeled for metadata lookup', () {
      expect(AudioSpectrumService.afSegment, contains('@dacxstats:'));
      expect(AudioSpectrumService.afSegment, contains('astats='));
      expect(AudioSpectrumService.afSegment, contains('acrossover='));
      expect(
        AudioSpectrumService.afSegment,
        contains('measure_perchannel=RMS_level'),
      );
    });

    testWidgets('audio spectrum visualizer builds', (tester) async {
      final stream = StreamController<List<double>>.broadcast();
      addTearDown(stream.close);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 40,
            child: AudioSpectrumVisualizer(
              isPlaying: false,
              position: Duration.zero,
              duration: const Duration(seconds: 1),
              spectrumStream: stream.stream,
            ),
          ),
        ),
      );

      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    test('player screen constructor smoke', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      final log = DebugLogService(isEnabled: () => false);
      final updates = UpdateService(
        debugLog: log,
        debugSource: 'coverage_smoke',
      );

      final screen = PlayerScreen(
        settings: settings,
        debugLog: log,
        updateService: updates,
      );

      expect(screen, isA<PlayerScreen>());
    });
  });
}
