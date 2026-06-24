import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/widgets/queue_item_tile.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('QueueItemTile keyboard behavior', () {
    testWidgets('Enter and Space activate item, Delete removes item', (
      tester,
    ) async {
      var activateCount = 0;
      var removeCount = 0;
      final node = FocusNode(debugLabel: 'queue-item');
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _wrap(
          QueueItemTile(
            focusNode: node,
            name: 'Track 1',
            isCurrent: false,
            isUrl: false,
            playLabel: 'Play',
            removeLabel: 'Remove',
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            onActivate: () => activateCount++,
            onRemove: () => removeCount++,
          ),
        ),
      );

      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activateCount, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(activateCount, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(removeCount, 1);
    });

    testWidgets('Arrow keys move focus between queue items', (tester) async {
      final firstNode = FocusNode(debugLabel: 'first-item');
      final secondNode = FocusNode(debugLabel: 'second-item');
      addTearDown(firstNode.dispose);
      addTearDown(secondNode.dispose);

      await tester.pumpWidget(
        _wrap(
          FocusTraversalGroup(
            child: Column(
              children: [
                QueueItemTile(
                  focusNode: firstNode,
                  name: 'Track 1',
                  isCurrent: false,
                  isUrl: false,
                  playLabel: 'Play',
                  removeLabel: 'Remove',
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
                  onActivate: () {},
                  onRemove: () {},
                ),
                QueueItemTile(
                  focusNode: secondNode,
                  name: 'Track 2',
                  isCurrent: true,
                  isUrl: true,
                  playLabel: 'Play',
                  removeLabel: 'Remove',
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
                  onActivate: () {},
                  onRemove: () {},
                ),
              ],
            ),
          ),
        ),
      );

      firstNode.requestFocus();
      await tester.pump();
      expect(firstNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(secondNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(firstNode.hasFocus, isTrue);
    });
  });

  testWidgets('exposes button semantics with activate and remove actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        QueueItemTile(
          name: 'Track 1',
          isCurrent: false,
          isUrl: false,
          playLabel: 'Play',
          removeLabel: 'Remove',
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          onActivate: () {},
          onRemove: () {},
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(QueueItemTile));
    expect(
      semantics,
      matchesSemantics(
        label: 'Track 1',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );
  });
}
