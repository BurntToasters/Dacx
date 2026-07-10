import 'package:dacx/theme/glass_decorations.dart';
import 'package:dacx/theme/window_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

  WindowVisuals glass() =>
      WindowVisuals.fromScheme(scheme, blurEnabled: true, blurStrength: 0.5);

  WindowVisuals flat() =>
      WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0.5);

  group('GlassDecorations extension', () {
    test('isGlass reflects blurEnabled', () {
      expect(glass().isGlass, isTrue);
      expect(flat().isGlass, isFalse);
    });

    group('shellGradient', () {
      test('uses window top and bottom colors', () {
        final v = glass();
        final gradient = v.shellGradient;
        expect(gradient.colors.first, v.windowTopColor);
        expect(gradient.colors.last, v.windowBottomColor);
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
      });
    });

    group('chromeDecoration', () {
      test('glass mode uses gradient', () {
        final deco = glass().chromeDecoration();
        expect(deco.gradient, isA<LinearGradient>());
        expect(deco.color, isNull);
      });

      test('flat mode uses solid color', () {
        final deco = flat().chromeDecoration();
        expect(deco.gradient, isNull);
        expect(deco.color, isNotNull);
      });

      test('borderOnTop puts border on top', () {
        final deco = glass().chromeDecoration(borderOnTop: true);
        final border = deco.border as Border;
        expect(border.top.color, isNotNull);
        expect(border.bottom, BorderSide.none);
      });

      test('default puts border on bottom', () {
        final deco = glass().chromeDecoration();
        final border = deco.border as Border;
        expect(border.bottom.color, isNotNull);
        expect(border.top, BorderSide.none);
      });

      test('custom borderSide is honored', () {
        const custom = BorderSide(color: Colors.red, width: 3);
        final deco = glass().chromeDecoration(borderSide: custom);
        final border = deco.border as Border;
        expect(border.bottom.color, Colors.red);
        expect(border.bottom.width, 3);
      });
    });

    group('panelDecoration', () {
      test('glass mode uses gradient and rim highlight shadow', () {
        final deco = glass().panelDecoration();
        expect(deco.gradient, isA<LinearGradient>());
        expect(deco.color, isNull);
        // Two box shadows in glass mode (drop + rim highlight)
        expect(deco.boxShadow!.length, 2);
      });

      test('flat mode uses solid color and single shadow', () {
        final deco = flat().panelDecoration();
        expect(deco.gradient, isNull);
        expect(deco.color, isNotNull);
        expect(deco.boxShadow!.length, 1);
      });

      test('custom borderRadius is applied', () {
        const radius = BorderRadius.all(Radius.circular(8));
        final deco = glass().panelDecoration(borderRadius: radius);
        expect(deco.borderRadius, radius);
      });

      test('has a border in both modes', () {
        expect(glass().panelDecoration().border, isNotNull);
        expect(flat().panelDecoration().border, isNotNull);
      });
    });

    group('overlayDecoration', () {
      test('glass mode uses gradient', () {
        final deco = glass().overlayDecoration();
        expect(deco.gradient, isA<LinearGradient>());
        expect(deco.color, isNull);
      });

      test('flat mode uses solid color', () {
        final deco = flat().overlayDecoration();
        expect(deco.gradient, isNull);
        expect(deco.color, isNotNull);
      });

      test('has a top border in both modes', () {
        final glassBorder = glass().overlayDecoration().border as Border;
        final flatBorder = flat().overlayDecoration().border as Border;
        expect(glassBorder.top.color, isNotNull);
        expect(flatBorder.top.color, isNotNull);
      });
    });
  });

  group('GlassPanel widget', () {
    testWidgets('renders child in glass mode with backdrop filter', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const Scaffold(body: GlassPanel(child: Text('content'))),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('no backdrop filter in flat mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [flat()]),
          home: const Scaffold(body: GlassPanel(child: Text('content'))),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('no backdrop filter when blurSigma is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const Scaffold(
            body: GlassPanel(blurSigma: 0, child: Text('c')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('GlassChrome widget', () {
    testWidgets('renders with height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const Scaffold(
            body: GlassChrome(height: 48, child: Text('bar')),
          ),
        ),
      );
      expect(find.text('bar'), findsOneWidget);
    });

    testWidgets('renders without height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [flat()]),
          home: const Scaffold(body: GlassChrome(child: Text('bar'))),
        ),
      );
      expect(find.text('bar'), findsOneWidget);
    });
  });

  group('GlassShellBackground widget', () {
    testWidgets('renders child in glass mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const GlassShellBackground(child: Text('shell')),
        ),
      );
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('renders child in flat mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [flat()]),
          home: const GlassShellBackground(child: Text('shell')),
        ),
      );
      expect(find.text('shell'), findsOneWidget);
    });
  });

  group('GlassOverlayBackground widget', () {
    testWidgets('renders child in glass mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const GlassOverlayBackground(child: Text('overlay')),
        ),
      );
      expect(find.text('overlay'), findsOneWidget);
    });

    testWidgets('renders child in flat mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [flat()]),
          home: const GlassOverlayBackground(child: Text('overlay')),
        ),
      );
      expect(find.text('overlay'), findsOneWidget);
    });
  });

  group('GlassDrawerBody widget', () {
    testWidgets('renders child in glass mode with blur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const Scaffold(body: GlassDrawerBody(child: Text('drawer'))),
        ),
      );
      expect(find.text('drawer'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('no blur in flat mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [flat()]),
          home: const Scaffold(body: GlassDrawerBody(child: Text('drawer'))),
        ),
      );
      expect(find.text('drawer'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('borderOnLeft false renders right border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [glass()]),
          home: const Scaffold(
            body: GlassDrawerBody(borderOnLeft: false, child: Text('d')),
          ),
        ),
      );
      expect(find.text('d'), findsOneWidget);
    });
  });
}
