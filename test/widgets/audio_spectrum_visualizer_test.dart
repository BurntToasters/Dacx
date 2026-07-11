import 'package:dacx/widgets/audio_spectrum_visualizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioSpectrumVisualizer', () {
    late ValueNotifier<List<double>> bands;

    setUp(() {
      bands = ValueNotifier<List<double>>(List<double>.filled(32, 0.0));
    });

    tearDown(() async {
      // Unmount before disposing the notifier so listeners are gone.
      // Individual tests pump empty widgets when needed.
    });

    Widget wrap({required bool isPlaying}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            width: 200,
            child: AudioSpectrumVisualizer(
              isPlaying: isPlaying,
              bandsListenable: bands,
            ),
          ),
        ),
      );
    }

    testWidgets('builds without error', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: false));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
    });

    testWidgets('reacts to spectrum data while playing', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      bands.value = List<double>.filled(32, 0.8);
      await tester.pump();
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
    });

    testWidgets('handles shorter band list than bar count', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      bands.value = List<double>.filled(10, 0.5);
      await tester.pump();
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
    });

    testWidgets('handles longer band list than bar count', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      bands.value = List<double>.filled(64, 0.5);
      await tester.pump();
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
    });

    testWidgets('transitions from playing to paused', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      bands.value = List<double>.filled(32, 0.9);
      await tester.pump();
      await tester.pumpWidget(wrap(isPlaying: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      bands.dispose();
    });

    testWidgets('disposes cleanly', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      bands.value = List<double>.filled(32, 0.5);
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byType(AudioSpectrumVisualizer), findsNothing);
      bands.dispose();
    });
  });
}
