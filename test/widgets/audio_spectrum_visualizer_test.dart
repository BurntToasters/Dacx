import 'dart:async';

import 'package:dacx/widgets/audio_spectrum_visualizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioSpectrumVisualizer', () {
    late StreamController<List<double>> controller;

    setUp(() {
      controller = StreamController<List<double>>.broadcast();
    });

    tearDown(() async {
      await controller.close();
    });

    Widget wrap({required bool isPlaying}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            width: 200,
            child: AudioSpectrumVisualizer(
              isPlaying: isPlaying,
              position: const Duration(seconds: 5),
              duration: const Duration(seconds: 100),
              spectrumStream: controller.stream,
            ),
          ),
        ),
      );
    }

    testWidgets('builds without error', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: false));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('reacts to spectrum data while playing', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));

      // Emit some energy.
      controller.add(List<double>.filled(32, 0.8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump(const Duration(milliseconds: 32));

      // Widget should still be present and rendering.
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('handles shorter band list than bar count', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(10, 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('handles longer band list than bar count', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(64, 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('transitions from playing to paused', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(32, 0.9));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      // Switch to paused.
      await tester.pumpWidget(wrap(isPlaying: false));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('transitions from paused to playing', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: false));
      await tester.pump();

      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(32, 0.6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('handles zero energy (idle)', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: false));
      controller.add(List<double>.filled(32, 0.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('handles stream switch on widget update', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(32, 0.5));
      await tester.pump();

      // Swap in a new stream.
      final newController = StreamController<List<double>>.broadcast();
      addTearDown(newController.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 40,
              width: 200,
              child: AudioSpectrumVisualizer(
                isPlaying: true,
                position: const Duration(seconds: 5),
                duration: const Duration(seconds: 100),
                spectrumStream: newController.stream,
              ),
            ),
          ),
        ),
      );
      newController.add(List<double>.filled(32, 0.7));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('handles zero duration (no progress)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 40,
              width: 200,
              child: AudioSpectrumVisualizer(
                isPlaying: true,
                position: Duration.zero,
                duration: Duration.zero,
                spectrumStream: controller.stream,
              ),
            ),
          ),
        ),
      );
      controller.add(List<double>.filled(32, 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.byType(AudioSpectrumVisualizer), findsOneWidget);
    });

    testWidgets('disposes cleanly', (tester) async {
      await tester.pumpWidget(wrap(isPlaying: true));
      controller.add(List<double>.filled(32, 0.5));
      await tester.pump();
      // Replace with empty widget to trigger dispose.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byType(AudioSpectrumVisualizer), findsNothing);
    });
  });
}
