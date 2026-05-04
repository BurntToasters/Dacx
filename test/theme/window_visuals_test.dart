import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/theme/window_visuals.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

  group('WindowVisuals.fromScheme', () {
    test('blur enabled produces semi-transparent shell colors', () {
      final v = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.5,
      );
      expect(v.blurEnabled, isTrue);
      expect(v.blurStrength, 0.5);
      expect(v.windowTopColor.a, lessThan(1.0));
      expect(v.barColor.a, lessThan(1.0));
      expect(v.contentColor.a, lessThan(1.0));
      expect(v.overlayColor.a, lessThan(1.0));
    });

    test('blur disabled produces opaque shell colors', () {
      final v = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: false,
        blurStrength: 0.5,
      );
      expect(v.blurEnabled, isFalse);
      expect(v.windowTopColor.a, 1.0);
      expect(v.windowBottomColor.a, 1.0);
      expect(v.barColor.a, closeTo(0.98, 0.001));
    });

    test('blurStrength is clamped to [0,1]', () {
      final low = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: -3,
      );
      final high = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 5,
      );
      expect(low.blurStrength, 0.0);
      expect(high.blurStrength, 1.0);
    });

    test('uiOpacity scales blurred-shell alpha', () {
      final dim = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.5,
        uiOpacity: 0.1,
      );
      final full = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.5,
        uiOpacity: 1.0,
      );
      expect(dim.windowTopColor.a, lessThan(full.windowTopColor.a));
    });

    test('uiOpacity is clamped to >= 0.05', () {
      // 0 is below the floor; should not throw and should produce valid alpha.
      final v = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.5,
        uiOpacity: 0,
      );
      expect(v.windowTopColor.a, greaterThan(0.0));
    });
  });

  group('WindowVisuals.copyWith / lerp', () {
    test('copyWith overrides only requested fields', () {
      final v = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.4,
      );
      final c = v.copyWith(blurEnabled: false, blurStrength: 0.9);
      expect(c.blurEnabled, isFalse);
      expect(c.blurStrength, 0.9);
      expect(c.barColor, v.barColor);
    });

    test('lerp interpolates between two visuals', () {
      final a = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.0,
      );
      final b = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: false,
        blurStrength: 1.0,
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.blurStrength, closeTo(0.5, 0.001));
      // t >= 0.5 picks the other side's blurEnabled.
      expect(mid.blurEnabled, isFalse);
      // Returns this when other is not a WindowVisuals.
      expect(a.lerp(null, 0.5), same(a));
    });
  });

  group('BuildContextWindowVisuals', () {
    testWidgets('exposes WindowVisuals from theme extension', (tester) async {
      final visuals = WindowVisuals.fromScheme(
        scheme,
        blurEnabled: true,
        blurStrength: 0.3,
      );
      late WindowVisuals captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [visuals]),
          home: Builder(
            builder: (context) {
              captured = context.windowVisuals;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured, same(visuals));
    });
  });
}
