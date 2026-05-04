import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/widgets/osd_overlay.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: Stack(children: [child])),
    ),
  );
}

void main() {
  group('OsdOverlay', () {
    testWidgets('renders title and timestamps when visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OsdOverlay(
            title: 'Hello.mp3',
            position: Duration(seconds: 30),
            duration: Duration(minutes: 3, seconds: 5),
            visible: true,
            transientMessage: null,
          ),
        ),
      );

      expect(find.text('Hello.mp3'), findsOneWidget);
      expect(find.text('00:30 / 03:05'), findsOneWidget);
    });

    testWidgets('formats hour-long durations with hours field', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OsdOverlay(
            title: 'Movie',
            position: Duration(hours: 1, minutes: 2, seconds: 3),
            duration: Duration(hours: 2, minutes: 5, seconds: 6),
            visible: true,
            transientMessage: null,
          ),
        ),
      );

      expect(find.text('1:02:03 / 2:05:06'), findsOneWidget);
    });

    testWidgets('hides header when visible is false', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OsdOverlay(
            title: 'Hidden.mp3',
            position: Duration.zero,
            duration: Duration(seconds: 10),
            visible: false,
            transientMessage: null,
          ),
        ),
      );

      // Title still in tree (AnimatedOpacity), but the parent opacity is zero.
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text('Hidden.mp3'),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('shows transient message and auto-hides it', (tester) async {
      const autoHide = Duration(milliseconds: 200);

      Widget build({String? transient}) => _wrap(
        OsdOverlay(
          title: 'Track',
          position: Duration.zero,
          duration: const Duration(minutes: 1),
          visible: true,
          transientMessage: transient,
          autoHide: autoHide,
        ),
      );

      await tester.pumpWidget(build(transient: null));
      expect(find.text('Volume 50%'), findsNothing);

      await tester.pumpWidget(build(transient: 'Volume 50%'));
      await tester.pump();
      // Visible now.
      final visibleOpacity = tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text('Volume 50%'),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(visibleOpacity, 1.0);

      // After autoHide elapses, opacity drops to zero.
      await tester.pump(autoHide + const Duration(milliseconds: 50));
      final hiddenOpacity = tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text('Volume 50%'),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(hiddenOpacity, 0.0);
    });

    testWidgets('blocks pointer events via IgnorePointer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OsdOverlay(
            title: 'X',
            position: Duration.zero,
            duration: Duration(seconds: 1),
            visible: true,
            transientMessage: null,
          ),
        ),
      );
      // OsdOverlay's root is an IgnorePointer; assert at least one descendant
      // of the OsdOverlay is one (multiple IgnorePointers may exist in the
      // surrounding MaterialApp scaffolding).
      expect(
        find.descendant(
          of: find.byType(OsdOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });
}
