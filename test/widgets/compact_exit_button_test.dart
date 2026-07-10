import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/widgets/compact_exit_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('CompactExitButton', () {
    testWidgets('renders exit button and responds to taps', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        _wrap(CompactExitButton(onPressed: () => pressed = true)),
      );

      final finder = find.byType(CompactExitButton);
      expect(finder, findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);

      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
    });

    testWidgets('hover state changes visual properties', (tester) async {
      await tester.pumpWidget(_wrap(CompactExitButton(onPressed: () {})));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 400));
      addTearDown(gesture.removePointer);

      // Verify decoration color when not hovered.
      final containerFinder = find.byType(AnimatedContainer);
      var container = tester.widget<AnimatedContainer>(containerFinder);
      var decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: 0.48));

      // Move mouse pointer inside the exit button area.
      await gesture.moveTo(tester.getCenter(find.byType(CompactExitButton)));
      await tester.pumpAndSettle();

      // Verify hovered state changes decoration color.
      container = tester.widget<AnimatedContainer>(containerFinder);
      decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: 0.72));

      // Exit hover.
      await gesture.moveTo(const Offset(400, 400));
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(containerFinder);
      decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: 0.48));
    });
  });
}
