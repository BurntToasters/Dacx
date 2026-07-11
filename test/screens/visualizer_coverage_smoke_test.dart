import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/audio_spectrum_service.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/audio_spectrum_visualizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('visualizer coverage smoke', () {
    test('audio spectrum filter segments are labeled for metadata lookup', () {
      expect(AudioSpectrumService.afSegment, contains('@dacxb0:'));
      expect(AudioSpectrumService.afSegment, contains('@dacxb3:'));
      expect(AudioSpectrumService.afSegment, contains('astats='));
      expect(AudioSpectrumService.afSegment, contains('metadata=1'));
      expect(AudioSpectrumService.afSegments, hasLength(4));
    });

    testWidgets('audio spectrum visualizer builds', (tester) async {
      final bands = ValueNotifier<List<double>>(List<double>.filled(32, 0.0));

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 40,
            width: 200,
            child: AudioSpectrumVisualizer(
              isPlaying: false,
              bandsListenable: bands,
            ),
          ),
        ),
      );

      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
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
